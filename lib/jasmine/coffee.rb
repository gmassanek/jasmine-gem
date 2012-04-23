require 'time'

# look folks, Pathname is in extlib. Learn it, use it.
require 'pathname'

require 'rack/utils'
require 'coffee_script'

module Rack
  class Coffee

    CACHE_CONTROL_TTL_DEFAULT = 86400

    attr_accessor :app, :urls, :root, :cache_compile_dir, :compile_without_closure, :cache_control, :request_prefix

    def initialize(app, opts={})
      @app = app
      @urls = [opts.fetch(:urls, '/javascripts')].flatten
      @root = Pathname.new(opts.fetch(:root) { Dir.pwd })
      @request_prefix = '/public'
      set_cache_header_opts(opts.fetch(:cache_control, false))
      @cache_compile_dir = if opts.fetch(:cache_compile, false)
        Pathname.new(Dir.mktmpdir)
      else
        nil
      end
      @compile_without_closure = opts.fetch(:bare, false)
    end

    def call(env)
      path = Utils.unescape(env["PATH_INFO"])
      new_path = path.gsub(/#{request_prefix}/,'')

      return app.call(env) unless own_path?(path)
      return forbidden if path.include?('..')

      desired_js_file = root + new_path.sub(%r{^/},'')
      if desired_js_file.file?
        source_files = [desired_js_file]
      else
        desired_coffee_file = root + new_path.sub(/\.js$/, '.coffee').sub(%r{^/},'') 
        if desired_coffee_file.file?
          source_files = [desired_coffee_file]
        else
          return app.call(env)
        end
      end

      last_modified = source_files.map {|file| file.mtime }.max
      return not_modified if check_modified_since(env, last_modified)
      brewed = source_files.map{|file| brew(file) }.join("\n")
      [200, headers_for(last_modified), [brewed]]
    end

    def set_cache_header_opts(given)
      given = [given].flatten.map{|i| String(i) }
      return if ['false', ''].include?(given.first)
      ttl = given.first.to_i > 0 ? given.shift : CACHE_CONTROL_TTL_DEFAULT
      pub = given.first == 'public' ? ', public' : ''
      @cache_control = "max-age=#{ttl}#{pub}"
    end

    def brew(file)
      p file
      if file.to_s[/\.coffee$/]
        if cache_compile_dir
          cache_file = cache_compile_dir + "#{file.mtime.to_i}_#{file.basename}"
          if cache_file.file?
            cache_file.read
          else
            brewed = compile(file.read)
            cache_file.open('w') {|f| f << brewed }
            brewed
          end
        else
          compile(file.read)
        end
      else
        file.read
      end
    end

    def compile(coffee)
      CoffeeScript.compile coffee, {:bare => compile_without_closure }
    end

    def not_modified
      [304, {}, ["Not modified"]]
    end

    def forbidden
      [403, {'Content-Type' => 'text/plain'}, ["Forbidden\n"]]
    end

    def check_modified_since(rack_env, last_modified)
      cache_time = rack_env['HTTP_IF_MODIFIED_SINCE']
      cache_time && last_modified <= Time.parse(cache_time)
    end

    def headers_for(mtime)
      headers = {
        'Content-Type' => 'application/javascript',
        'Last-Modified' => mtime.httpdate
      }
      headers['Cache-Control'] = @cache_control if @cache_control
      headers
    end

    def own_path?(path)
      p path
      p urls
      path[/^#{request_prefix}/]
    end
  end
end

