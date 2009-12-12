module Hominid
  class Base

    # MailChimp API Documentation: http://www.mailchimp.com/api/1.2/
    MAILCHIMP_API_VERSION = "1.2"

    def initialize(config = {})
      if defined?(Rails.root) && (!config || config.empty?)
        config = YAML.load(File.open("#{Rails.root}/config/hominid.yml"))[Rails.env].symbolize_keys
      end
      config ||= {}
      config[:api_key] ||= @@api_key
      api_endpoint = config[:api_key].split('-').last
      config.merge(:username => config[:username].to_s, :password => config[:password].to_s)
      defaults = {:send_welcome       => false,
                  :double_opt_in      => false,
                  :update_existing    => true,
                  :replace_interests  => true,
                  :merge_tags         => {},
                  :secure             => false}
      @config = defaults.merge(config).freeze
      if config[:secure]
        @chimpApi = XMLRPC::Client.new2("https://#{api_endpoint}.api.mailchimp.com/#{MAILCHIMP_API_VERSION}/")
      else
        @chimpApi = XMLRPC::Client.new2("http://#{api_endpoint}.api.mailchimp.com/#{MAILCHIMP_API_VERSION}/")
      end
    end

    # Security related methods
    # --------------------------------

    def self.api_key=(value)
      @@api_key=value
    end

    def add_api_key
      @chimpApi.call("apikeyAdd", *@config.values_at(:username, :password, :api_key))
    end

    def expire_api_key
      @chimpApi.call("apikeyExpire", *@config.values_at(:username, :password, :api_key))
    end

    def api_keys(include_expired = false)
      username, password = *@config.values_at(:username, :password)
      @chimpApi.call("apikeys", username, password, include_expired)
    end

    # Used internally by Hominid
    # --------------------------------

    # handle common cases for which the Mailchimp API would raise Exceptions
    def clean_merge_tags(merge_tags)
      return {} unless merge_tags.is_a? Hash
      merge_tags.each do |key, value|
        if merge_tags[key].is_a? String
          merge_tags[key] = value.gsub("\v", '')
        elsif merge_tags[key].nil?
          merge_tags[key] = ''
        end
      end
    end

    def apply_defaults_to(options)
      @config.merge(options)
    end

    def call(method, *args)
      @chimpApi.call(method, @config[:api_key], *args)
    rescue XMLRPC::FaultException => error
      case error.faultCode
      when 230
        raise AlreadySubscribed.new(error)
      when 231
        raise AlreadyUnsubscribed.new(error)
      when 232
        raise NotExists.new(error)
      when 233, 215
        raise NotSubscribed.new(error)
      else
        raise APIError.new(error)
      end
    rescue RuntimeError => error
      if error.message =~ /Wrong type NilClass\. Not allowed!/
        hashes = args.select{|a| a.is_a? Hash}
        errors = hashes.select{|k, v| v.nil? }.collect{ |k, v| "#{k} is Nil." }.join(' ')
        raise CommunicationError.new(errors)
      else
        raise error
      end
    rescue Exception => error
      raise CommunicationError.new(error.message)
    end
  end
end

