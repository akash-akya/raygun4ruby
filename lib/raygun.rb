require "httparty"
require "logger"
require "json"
require "socket"
require "rack"
require "ostruct"

require "raygun/version"
require "raygun/configuration"
require "raygun/client"
require "raygun/middleware/rack_exception_interceptor"
require "raygun/testable"
require "raygun/affected_user"
require "raygun/services/apply_whitelist_filter_to_payload"
require "raygun/railtie" if defined?(Rails)
begin
  require "pry"
rescue LoadError
end

module Raygun

  # used to identify ourselves to Raygun
  CLIENT_URL  = "https://github.com/MindscapeHQ/raygun4ruby"
  CLIENT_NAME = "Raygun4Ruby Gem"

  class << self

    include Testable

    # Configuration Object (instance of Raygun::Configuration)
    attr_writer :configuration

    def setup
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def default_configuration
      configuration.defaults
    end

    def configured?
      !!configuration.api_key
    end

    def track_exception(exception_instance, env = {}, retry_count = 1)
      if should_report?(exception_instance)
        log("[Raygun] Tracking Exception...")
        Client.new.track_exception(exception_instance, env)
      end
    rescue Exception => e
      if configuration.failsafe_logger
        failsafe_log("Problem reporting exception to Raygun: #{e.class}: #{e.message}\n\n#{e.backtrace.join("\n")}")
      end

      if retry_count > 0
        new_exception = e.exception("raygun4ruby encountered an exception processing your exception")
        new_exception.set_backtrace(e.backtrace)

        env[:custom_data] ||= {}
        env[:custom_data].merge!(original_stacktrace: exception_instance.backtrace)

        track_exception(new_exception, env, retry_count - 1)
      else
        raise e
      end
    end

    def track_exceptions
      yield
    rescue => e
      track_exception(e)
    end

    def log(message)
      configuration.logger.info(message) if configuration.logger
    end

    def failsafe_log(message)
      configuration.failsafe_logger.info(message)
    end

    def deprecation_warning(message)
      if defined?(ActiveSupport::Deprecation)
        ActiveSupport::Deprecation.warn(message)
      else
        puts message
      end
    end

    private

      def print_api_key_warning
        $stderr.puts(NO_API_KEY_MESSAGE)
      end

      def should_report?(exception)
        return false if configuration.silence_reporting
        return false if configuration.ignore.flatten.include?(exception.class.to_s)
        true
      end

  end
end
