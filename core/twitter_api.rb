#
# twitter_api.rb - Twitter API class
#
# Copyright (c) 2007, 2008 Katsuhiko Ichinose <ichi@users.sourceforge.jp>
#
# GNU General Public License version 2 is applied to this program.
#
# $Id: twitter_api.rb 164 2009-01-23 09:40:37Z ichi $
require 'net/http'
require 'thread'
require 'base64'
require 'io/wait'
miquire :lib, 'escape'
miquire :lib, 'oauth'
miquire :plugin, 'plugin'

Net::HTTP.version_1_2
=begin
class TwitterAPI
=end
class TwitterAPI < Mutex
  HOST = 'twitter.com'
  OPEN_TIMEOUT = 10
  READ_TIMEOUT = 20
  FORMAT = 'json'
  API_MAX = 150
  API_RESET_INTERVAL = 3600
  OAUTH_VERSION = '1.0'
  CONSUMER_KEY = "AmDS1hCCXWstbss5624kVw"
  CONSUMER_SECRET = "KOPOooopg9Scu7gJUBHBWjwkXz9xgPJxnhnhO55VQ"

  include ConfigLoader

  @@failed_lock = Monitor.new
  @@last_success = nil
  @@testmode = false
  @@ntr = '200'

  def initialize(a_token, a_secret, &fail_trap)
    super()
    @a_token, @a_secret = a_token, a_secret
    @getmutex = Mutex.new
    if(fail_trap) then
      @fail_trap = fail_trap
    else
      @fail_trap = nil
    end
  end

  def self.testmode
    @@testmode = true
  end

  def self.next_test_response=(ntr)
    @@ntr = ntr
  end

  def api_remain(response = nil)
    if response and response['X-RateLimit-Reset'] then
      @api_remain = [ response['X-RateLimit-Limit'].to_i,
                      response['X-RateLimit-Remaining'].to_i,
                      Time.at(response['X-RateLimit-Reset'].to_i) ]
    end
    return *@api_remain
  end

  def user
    nil
  end

  def connection
    http = Net::HTTP.new(HOST)
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    return http
  end

  def request(method, url, body = nil, headers = {})
    method = method.to_s
    url = URI.parse(url)
    request = create_http_request(method, url, body, headers)
    request['Authorization'] = auth_header(method, url, request.body)
    Net::HTTP.new(url.host, url.port).request(request)
  end

  def create_http_request(method, path, body, headers)
    method = method.capitalize.to_sym
    request = Net::HTTP.const_get(method).new(path.to_s)
    headers.each{ |pair|
      request[pair[0]] = pair[1] }
    request['User-Agent'] = Config::NAME + '/' + Config::VERSION.join('.')
    if method == :Post || method == :Put
      request.body = body.is_a?(Hash) ? encode_parameters(body) : body.to_s
      request.content_type = 'application/x-www-form-urlencoded'
      request.content_length = (request.body || '').length
    end
    request
  end

  def request_oauth_token
    OAuth::Consumer.new(CONSUMER_KEY,
                        CONSUMER_SECRET,
                        :site => "http://twitter.com").get_request_token
  end

  def auth_header(method, url, body)
    parameters = oauth_parameters
    parameters[:oauth_signature] = signature(method, url, body, parameters)
    'OAuth ' + encode_parameters(parameters, ', ', '"')
  end

  def signature(*args)
    [digest_hmac_sha1(signature_base_string(*args))].pack('m').gsub(/\n/, '')
  end

  def digest_hmac_sha1(value)
    OpenSSL::HMAC.digest(OpenSSL::Digest::SHA1.new, secret, value)
  end

  def secret
    escape(CONSUMER_SECRET) + '&' + escape(@a_secret)
  end

  def signature_base_string(method, url, body, parameters)
    method = method.upcase
    base_url = signature_base_url(url)
    parameters = normalize_parameters(parameters, body, url.query)
    encode_parameters([ method, base_url, parameters ])
  end

  def signature_base_url(url)
    URI::HTTP.new(url.scheme, url.userinfo, url.host, nil, nil, url.path, nil, nil, nil)
  end

  def normalize_parameters(parameters, body, query)
    parameters = encode_parameters(parameters, nil)
    parameters += body.split('&') if body
    parameters += query.split('&') if query
    parameters.sort.join('&')
  end

  def encode_parameters(params, delimiter = '&', quote = nil)
    if params.is_a?(Hash)
      params = params.map do |key, value|
        "#{escape(key)}=#{quote}#{escape(value)}#{quote}"
      end
    else
      params = params.map { |value| escape(value) }
    end
    delimiter ? params.join(delimiter) : params
  end

  def escape(value)
    URI.escape(value.to_s, /[^a-zA-Z0-9\-\.\_\~]/)
  end


  def oauth_parameters
    {
      :oauth_consumer_key => CONSUMER_KEY,
      :oauth_token => @a_token,
      :oauth_signature_method => 'HMAC-SHA1',
      :oauth_timestamp => timestamp,
      :oauth_nonce => nonce,
      :oauth_version => OAUTH_VERSION
    }
  end

  def timestamp
    Time.now.to_i.to_s
  end

  def nonce
    OpenSSL::Digest::Digest.hexdigest('MD5', "#{Time.now.to_f}#{rand}")
  end

  def get(path, head)
    return get_file(path) if(@@testmode and get_file(path))
    res = nil
    http = nil
    begin
      http = self.connection()
      http.start
      res = http.get(path, head)
    rescue Exception => evar
      res = evar
    ensure
      begin
        http.finish if http.active?
      rescue Exception => evar
        Log.warn('TwitterAPI.get:finish') do "#{evar.inspect}" end
      end
    end
    notice "#{path} => #{res}"
    get_save(res, path) if @@testmode
    res
  end

  def get_with_auth(path, head)
    res = nil
    begin
      res = request('GET', 'http://twitter.com'+path, nil, head)
    rescue Exception => evar
      res = evar
    end
    notice "#{path} => #{res}"
    if res.is_a?(Net::HTTPResponse) then
      limit, remain, reset = self.api_remain(res)
      if(res.code == '200') then
        Plugin::Ring::call(nil, :apiremain, self, remain, reset)
      elsif(res.code == '401') then
        if @fail_trap then
          last_success = @@last_success
          @@failed_lock.synchronize{
            if(@@last_success == last_success) then
              @@last_success = @fail_trap.call()
            end
            @a_token, @a_secret, callback = *@@last_success
            callback.call if callback
            res = self.get_with_auth(path, head)
          }
        end
      end
    end
    res
  end

  def get_file(path)
    cachefn = File::expand_path('~/.mikutter/queries/' + path + '/200')
    if(FileTest::exist?(cachefn))
      return Class.new{
        attr_reader :code

        def initialize(cachefn, res)
          @cachefn = cachefn
          @code = res
        end

        def body
          file_get_contents(@cachefn)
        end
      }.new(cachefn, @@ntr)
    end
  end

  def get_save(res, path)
    if defined? res.code
      cachefn = File::expand_path('~/.mikutter/queries/' + path + '/' + res.code)
      FileUtils.mkdir_p(File::dirname(cachefn))
      file_put_contents(cachefn, res.body)
    end
  end

  def post(path, data, head)
    res = nil
    http = nil
    begin
      notice "post: try #{path}(#{data.inspect})"
      res = request('POST', 'http://twitter.com'+path, data, head)
    rescue Exception => evar
      res = evar
    end
    notice "#{path} => #{res}(#{(defined?(res.body) and res.body)})"
    res
  end

  def post_with_auth(path, data, head)
    post(path, data, head)
  end

  def option_since(since)
    since.httpdate =~ /^(.*?), (\S+) (\S+) (\S+) (\S+) (\S+)/
    $1+'%2C+'+$2+'+'+$3+'+'+$4+'+'+$5+'+'+$6
  end

  def public_timeline(since = nil)
    path = '/statuses/public_timeline.' + FORMAT
    path += "?since_id=#{since}" if since
    head = {'Host' => HOST}
    get(path, head)
  end

  def friends_timeline(args = {})
    path = '/statuses/home_timeline.' + FORMAT + get_args(args)
    head = {'Host' => HOST}
    get_with_auth(path, head)
  end

  def replies(args = {})
    path = '/statuses/mentions.' + FORMAT + get_args(args)
    head = {'Host' => HOST}
    get_with_auth(path, head)
  end

  def search(args = {})
    path = '/search.' + FORMAT + get_args(args)
    head = {'Host' => HOST}
    get(path, head)
  end

  def retweeted_to_me(args = {})
    path = "/statuses/retweeted_to_me.#{FORMAT}" + get_args(args)
    head = {'Host' => HOST}
    get_with_auth(path, head)
  end

  def retweets_of_me(args = {})
    path = "/statuses/retweets_of_me.#{FORMAT}" + get_args(args)
    head = {'Host' => HOST}
    get_with_auth(path, head)
  end

  def friends(args = {})
    path = '/statuses/friends.' + FORMAT + get_args(args)
    head = {'Host' => HOST}
    get_with_auth(path, head)
  end

  def followers(args = {})
    path = '/statuses/followers.' + FORMAT + get_args(args)
    head = {'Host' => HOST}
    get_with_auth(path, head)
  end

  def direct_messages(since = nil)
    path = '/direct_messages.' + FORMAT
    path += "?since=#{option_since(since)}" if since
    head = {'Host' => HOST}
    get_with_auth(path, head)
  end

  def user_show(args)
    path = "/users/show." + FORMAT + get_args(args)
    head = {'Host' => HOST}
    get(path, head)
  end

  def status_show(args)
    path = "/statuses/show/#{args[:id]}.#{FORMAT}"
    head = {'Host' => HOST}
    get(path, head)
  end

  def saved_searches(args=nil)
    get_with_auth('/saved_searches.' + FORMAT, {'Host' => HOST})
  end

  def rate_limit_status(args=nil)
    path = "/account/rate_limit_status.#{FORMAT}"
    head = {'Host' => HOST}
    get_with_auth(path, head)
  end

  def verify_credentials(args=nil)
    path = "/account/verify_credentials.#{FORMAT}"
    head = {'Host' => HOST}
    get_with_auth(path, head)
  end

  def update(status, reply_to = nil)
    path = '/statuses/update.' + FORMAT
    enc = URI.encode(status, /[^a-zA-Z0-9\'\.\-\*\(\)\_]/n)
    data = 'status=' + enc
    data += '&in_reply_to_status_id=' + reply_to.to_s if reply_to
    # data += '&source=' + PROG_NAME
    head = {'Host' => HOST}
    post_with_auth(path, data, head)
  end

  def retweet(msg)
    post_with_auth("/statuses/retweet/#{msg[:id]}.#{FORMAT}", '', 'Host' => HOST)
  end

  def destroy(msg)
    post_with_auth("/statuses/destroy/#{msg[:id]}.#{FORMAT}", '', 'Host' => HOST)
  end

  def search_create(query)
    post_with_auth("/saved_searches/create.#{FORMAT}", "query=#{URI.encode(query)}", 'Host' => HOST)
  end

  def send(user, text)
    path = '/direct_messages/new.' + FORMAT
    data = "user=" + URI.encode(user)
    data += "&text=" + URI.encode(text)
    data += '&source=' + PROG_NAME
    head = {'Host' => HOST}
    res = post_with_auth(path, data, head)
    res
  end

  def favorite(id)
    path = "/favorites/create/#{id}." + FORMAT
    data = ''
    head = {'Host' => HOST}
    res = post_with_auth(path, data, head)
    res
  end

  def unfavorite(id)
    path = "/favorites/destroy/#{id}." + FORMAT
    data = ''
    head = {'Host' => HOST}
    res = post_with_auth(path, data, head)
    res
  end

  def follow(user)
    data = ''
    head = {'Host' => HOST}
    post_with_auth("/friendships/create/#{user[:id]}.#{FORMAT}", data, head)
  end

  def get_args(args)
    if not args.empty?
      "?" + args.map{|k, v| "#{Escape.uri_segment(k.to_s).to_s}=#{Escape.uri_segment(v.to_s).to_s}"}.join('&')
    else
      ''
    end
  end
end
# ~> -:13: undefined method `miquire' for main:Object (NoMethodError)
