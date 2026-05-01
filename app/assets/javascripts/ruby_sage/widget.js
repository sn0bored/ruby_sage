(function() {
  "use strict";

  // Idempotent mount: works under Turbo or full page loads.
  function mount() {
    var root = document.getElementById("ruby-sage-root");
    if (!root || root.dataset.rubySageMounted === "true") return;
    root.dataset.rubySageMounted = "true";

    var mountPath = root.dataset.mount || "/ruby_sage";
    renderWidget(root, mountPath);
  }

  function unmount() {
    var root = document.getElementById("ruby-sage-root");
    if (root) delete root.dataset.rubySageMounted;
  }

  function renderWidget(root, mountPath) {
    var button = document.createElement("button");
    button.type = "button";
    button.className = "ruby-sage-button";
    button.setAttribute("aria-label", "Open codebase chat");
    button.textContent = "Ask";
    root.appendChild(button);

    var drawer = createDrawer(mountPath);
    document.body.appendChild(drawer);

    button.addEventListener("click", function() {
      drawer.classList.toggle("ruby-sage-drawer--open");
      var input = drawer.querySelector(".ruby-sage-input");
      if (drawer.classList.contains("ruby-sage-drawer--open") && input) input.focus();
    });
  }

  function createDrawer(mountPath) {
    var drawer = document.createElement("aside");
    drawer.className = "ruby-sage-drawer";
    drawer.innerHTML =
      '<header class="ruby-sage-header">' +
        '<span class="ruby-sage-title">RubySage</span>' +
        '<button type="button" class="ruby-sage-close" aria-label="Close">x</button>' +
      "</header>" +
      '<div class="ruby-sage-thread" role="log" aria-live="polite"></div>' +
      '<form class="ruby-sage-form">' +
        '<input class="ruby-sage-input" type="text" placeholder="Ask about this codebase..." autocomplete="off" />' +
        '<button type="submit" class="ruby-sage-submit">Send</button>' +
      "</form>";

    drawer.querySelector(".ruby-sage-close").addEventListener("click", function() {
      drawer.classList.remove("ruby-sage-drawer--open");
    });

    var thread = drawer.querySelector(".ruby-sage-thread");
    var form = drawer.querySelector(".ruby-sage-form");
    var input = drawer.querySelector(".ruby-sage-input");

    form.addEventListener("submit", function(event) {
      event.preventDefault();
      var message = (input.value || "").trim();
      if (!message) return;
      input.value = "";
      appendMessage(thread, "user", message);

      var pending = appendMessage(thread, "assistant", "...");
      pending.classList.add("ruby-sage-pending");

      sendChat(mountPath, message, getPageContext(), function(err, response) {
        pending.classList.remove("ruby-sage-pending");
        if (err) {
          pending.textContent = "Error: " + err.message;
          pending.classList.add("ruby-sage-error");
          return;
        }
        renderAnswer(pending, response);
      });
    });

    return drawer;
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
    var answer = document.createElement("div");
    answer.className = "ruby-sage-answer";
    answer.textContent = response.answer || "(no answer)";
    node.appendChild(answer);

    if (response.citations && response.citations.length) {
      var list = document.createElement("ul");
      list.className = "ruby-sage-citations";
      response.citations.forEach(function(c) {
        var item = document.createElement("li");
        item.textContent = c.path + " (" + c.kind + ")";
        list.appendChild(item);
      });
      node.appendChild(list);
    }
  }

  function getPageContext() {
    return { url: window.location.href, title: document.title };
  }

  // V1: single fetch. Swapping JSON for SSE later should stay localized here.
  function sendChat(mountPath, message, pageContext, callback) {
    var url = mountPath.replace(/\/$/, "") + "/chat";
    var token = csrfToken();
    var headers = { "Content-Type": "application/json", "Accept": "application/json" };
    if (token) headers["X-CSRF-Token"] = token;

    fetch(url, {
      method: "POST",
      credentials: "same-origin",
      headers: headers,
      body: JSON.stringify({ message: message, page_context: pageContext })
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
