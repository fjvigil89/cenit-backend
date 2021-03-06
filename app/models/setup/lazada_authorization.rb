module Setup
  class LazadaAuthorization < Setup::Oauth2Authorization
    include CenitScoped

    build_in_data_type.referenced_by(:namespace, :name)

    auth_template_parameters access_token: ->(oauth2_auth) { oauth2_auth.fresh_access_token }

    def create_http_client(options = {})
      super(options.merge(auth_scheme: :none))
    end

    def token_params(params = {}, template_parameters = {})
      super
      sign_params(params, url: client.provider.token_endpoint, skip_access_token: true)
      params
    end

    def sign_params(params, template_parameters = {})
      params['access_token'] = access_token unless template_parameters[:skip_access_token]
      path = URI.parse(
        template_parameters[:url].to_s.gsub(%r{\/+\Z}, '').strip +
          ('/' + template_parameters[:path].to_s).gsub(%r{\/+}, '/').strip
      ).path.to_s
      path.gsub!(/\A\/rest/, '')
      path.gsub!(/\/\Z/, '')
      self.class.sign_params(client, path, params)
      super
    end

    class << self
      def sign_params(client, path, params)
        params['app_key'] = client.get_identifier
        params['sign_method'] = 'sha256'
        params['timestamp'] = (Time.now.utc.to_f * 1000).to_i
        sign = (path + params.sort.flatten.join).hmac_hex_sha256(client.get_secret).upcase
        params['sign'] = sign
      end
    end
  end
end
