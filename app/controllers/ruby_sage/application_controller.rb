# frozen_string_literal: true

module RubySage
  class ApplicationController < ::ActionController::Base
    before_action :authorize_ruby_sage!

    private

    def authorize_ruby_sage!
      return if RubySage.configuration.auth_check&.call(self) == true || permissive_scope?

      head :forbidden
    end

    def permissive_scope?
      case RubySage.configuration.scope
      when :public_rate_limited then true
      when :signed_in then signed_in_user?
      else false
      end
    end

    def signed_in_user?
      respond_to?(:current_user) && current_user.present?
    end
  end
end
