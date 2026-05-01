(function() {
  "use strict";

  // Idempotent mount: works under Turbo or full page loads.
  function mount() {
    var root = document.getElementById("ruby-sage-root");
    if (!root || root.dataset.rubySageMounted === "true") return;
    root.dataset.rubySageMounted = "true";

    var mountPath = root.dataset.mount || "/ruby_sage";
    var mode = root.dataset.mode || "developer";
    renderWidget(root, mountPath, mode);
  }

  function unmount() {
    var root = document.getElementById("ruby-sage-root");
    if (root) delete root.dataset.rubySageMounted;
  }

  function renderWidget(root, mountPath, mode) {
    var button = document.createElement("button");
    button.type = "button";
    button.className = "ruby-sage-button";
    button.setAttribute("aria-label", "Open codebase chat");
    button.textContent = "How does this work?";
    root.appendChild(button);

    var drawer = createDrawer(mountPath, mode);
    document.body.appendChild(drawer);

    button.addEventListener("click", function() {
      drawer.classList.toggle("ruby-sage-drawer--open");
      var input = drawer.querySelector(".ruby-sage-input");
      if (drawer.classList.contains("ruby-sage-drawer--open") && input) input.focus();
    });
  }

  var STARTER_QUESTIONS = {
    developer: [
      "What are the main models and how do they relate?",
      "How does authentication work?",
      "Walk me through the main user workflow.",
      "What background jobs are there and what do they do?"
    ],
    admin: [
      "What features are available and how do they work?",
      "Walk me through the main user workflows.",
      "What roles and permissions exist in this app?",
      "How does the billing or subscription system work?"
    ],
    user: [
      "How do I get started?",
      "What can I do on this page?",
      "How do I update my account or settings?",
      "How do I contact support?"
    ]
  };

  function createDrawer(mountPath, mode) {
    var history = [];  // conversation history for this drawer instance
    var starterQuestions = (STARTER_QUESTIONS[mode] || STARTER_QUESTIONS.developer);

    var drawer = document.createElement("aside");
    drawer.className = "ruby-sage-drawer";
    drawer.innerHTML =
      '<header class="ruby-sage-header">' +
        '<span class="ruby-sage-title">RubySage</span>' +
        '<button type="button" class="ruby-sage-clear" aria-label="Clear conversation" title="Clear conversation">&#8635;</button>' +
        '<button type="button" class="ruby-sage-close" aria-label="Close">&#x2715;</button>' +
      "</header>" +
      '<div class="ruby-sage-thread" role="log" aria-live="polite">' +
        '<div class="ruby-sage-starters" aria-label="Suggested questions"></div>' +
      "</div>" +
      '<form class="ruby-sage-form">' +
        '<input class="ruby-sage-input" type="text" placeholder="Ask about this page or your whole codebase..." autocomplete="off" />' +
        '<button type="submit" class="ruby-sage-submit">Send</button>' +
      "</form>";

    var thread = drawer.querySelector(".ruby-sage-thread");
    var starters = drawer.querySelector(".ruby-sage-starters");
    var form = drawer.querySelector(".ruby-sage-form");
    var input = drawer.querySelector(".ruby-sage-input");

    drawer.querySelector(".ruby-sage-close").addEventListener("click", function() {
      drawer.classList.remove("ruby-sage-drawer--open");
    });

    drawer.querySelector(".ruby-sage-clear").addEventListener("click", function() {
      history = [];
      thread.innerHTML = "";
      thread.appendChild(starters);
      starters.style.display = "";
    });

    starterQuestions.forEach(function(question) {
      var chip = document.createElement("button");
      chip.type = "button";
      chip.className = "ruby-sage-starter";
      chip.textContent = question;
      chip.addEventListener("click", function() {
        starters.style.display = "none";
        input.value = question;
        form.dispatchEvent(new Event("submit", { cancelable: true, bubbles: true }));
      });
      starters.appendChild(chip);
    });

    form.addEventListener("submit", function(event) {
      event.preventDefault();
      var message = (input.value || "").trim();
      if (!message) return;
      input.value = "";
      starters.style.display = "none";

      history.push({ role: "user", content: message });
      appendMessage(thread, "user", message);

      var pending = appendMessage(thread, "assistant", "...");
      pending.classList.add("ruby-sage-pending");
      setFormDisabled(form, true);

      sendChat(mountPath, history, getPageContext(), function(err, response) {
        pending.classList.remove("ruby-sage-pending");
        setFormDisabled(form, false);
        input.focus();

        if (err) {
          pending.textContent = "Something went wrong. Please try again.";
          pending.classList.add("ruby-sage-error");
          // Remove the failed user message from history so it can be retried.
          history.pop();
          return;
        }

        history.push({ role: "assistant", content: response.answer || "" });
        renderAnswer(pending, response);
      });
    });

    return drawer;
  }

  function setFormDisabled(form, disabled) {
    var input = form.querySelector(".ruby-sage-input");
    var submit = form.querySelector(".ruby-sage-submit");
    if (input) input.disabled = disabled;
    if (submit) submit.disabled = disabled;
  }

  function appendMessage(thread, role, text) {
    var row = document.createElement("div");
    row.className = "ruby-sage-message ruby-sage-message--" + role;
    row.textContent = text;
    thread.appendChild(row);
    thread.scrollTop = thread.scrollHeight;
    return row;
  }

  function renderAnswer(node, response) {
    node.textContent = "";

    var answer = document.createElement("p");
    answer.className = "ruby-sage-answer";
    answer.textContent = response.answer || "(no answer)";
    node.appendChild(answer);

    var citations = (response.citations || []).filter(function(c) { return c.snippet; });
    if (!citations.length) return;

    var details = document.createElement("details");
    details.className = "ruby-sage-sources";
    var summary = document.createElement("summary");
    summary.textContent = citations.length === 1 ? "1 source" : citations.length + " sources";
    details.appendChild(summary);

    var list = document.createElement("ul");
    citations.forEach(function(c) {
      var item = document.createElement("li");
      var snippet = document.createElement("span");
      snippet.className = "ruby-sage-source-snippet";
      snippet.textContent = c.snippet;
      var path = document.createElement("code");
      path.className = "ruby-sage-source-path";
      path.textContent = c.path;
      item.appendChild(snippet);
      item.appendChild(path);
      list.appendChild(item);
    });
    details.appendChild(list);
    node.appendChild(details);
  }

  function getPageContext() {
    return { url: window.location.href, title: document.title };
  }

  // V1: single fetch. Swapping JSON for SSE in v1.5 should stay localized here.
  function sendChat(mountPath, messages, pageContext, callback) {
    var url = mountPath.replace(/\/$/, "") + "/chat";
    var token = csrfToken();
    var headers = { "Content-Type": "application/json", "Accept": "application/json" };
    if (token) headers["X-CSRF-Token"] = token;

    fetch(url, {
      method: "POST",
      credentials: "same-origin",
      headers: headers,
      body: JSON.stringify({ messages: messages, page_context: pageContext })
    })
      .then(function(r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function(json) { callback(null, json); })
      .catch(function(err) { callback(err); });
  }

  function csrfToken() {
    var meta = document.querySelector("meta[name='csrf-token']");
    return meta ? meta.getAttribute("content") : null;
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", mount);
  } else {
    mount();
  }
  document.addEventListener("turbo:load", mount);
  document.addEventListener("turbo:before-cache", unmount);
})();
