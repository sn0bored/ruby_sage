# frozen_string_literal: true

module RubySage
  # Renders the floating chat widget. Place in any layout.
  #
  # @example
  #   <%# in app/views/layouts/application.html.erb %>
  #   <%= ruby_sage_widget %>
  module WidgetHelper
    # Renders the floating chat widget when the current visibility scope allows it.
    #
    # @return [ActiveSupport::SafeBuffer, String]
    def ruby_sage_widget
      return "" unless ruby_sage_widget_visible?

      render(partial: "ruby_sage/widget/widget")
    end

    # Resolves the CSP nonce used by the widget script tag.
    #
    # @return [String, nil]
    def ruby_sage_csp_nonce
      callable = RubySage.configuration.csp_nonce
      return nil unless callable

      callable.call(self)
    rescue StandardError
      nil
    end

    private

    def ruby_sage_widget_visible?
      config = RubySage.configuration

      case config.scope
      when :public_rate_limited then true
      when :signed_in then ruby_sage_signed_in?
      else config.auth_check&.call(self) == true
      end
    end

    def ruby_sage_signed_in?
      respond_to?(:current_user) && current_user.present?
    end
  end
end
