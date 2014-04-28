class Configuration
  APP_CONFIG_FILE = File.join(APP_ROOT, '.ebm', 'config.yml')
  APP_OPTION_SETTINGS_FILE = File.join(APP_ROOT, '.ebm', 'optionsettings.yml')
  AWS_CREDENTIAL_FILE = ENV['AWS_CREDENTIAL_FILE']
  CONFIGURATION_LIST = %w[app env cname_prefix eb_bucket eb_key_prefix solution_stack]
  
  attr_reader :aws_credential, :command_opts, :config, :option_settings
  
  def initialize
    @aws_credential = {}
    @command_opts = {}
    @config = {}
    @option_settings = []
    parse_command_line_options
    load_config_file
    load_option_settings_file
    load_aws_credential_file
  end
  
  # List of Required Configuration Options
  
  def self.list
    CONFIGURATION_LIST
  end
  
  # Configuration Sources
  
  def load_aws_credential_file
    handle_error(:aws_credential_file_envvar_not_set) if AWS_CREDENTIAL_FILE.nil?
    if File.exist?(AWS_CREDENTIAL_FILE)
      File.open(AWS_CREDENTIAL_FILE, 'r').each_line do |line|
        key, value = line.partition('=')[0].strip, line.partition('=')[2].strip
        case key
        when 'AWSAccessKeyId'
          @aws_credential[:access_key_id] = value
        when 'AWSSecretKey'
          @aws_credential[:secret_access_key] = value
        end
      end
      handle_error(:aws_credential_file_invalid) if (@aws_credential[:access_key_id].nil? || @aws_credential[:secret_access_key].nil?)
    else
      handle_error :aws_credential_file_not_found
    end
  end
  
  def load_config_file
    if File.exist?(APP_CONFIG_FILE)
      ['all', @command_opts[:stage]].each do |stage|
        @config.merge!(YAML.load_file(APP_CONFIG_FILE)[stage]) if YAML.load_file(APP_CONFIG_FILE)[stage]
      end
      @config = Hash[@config.map{ |key, value| [key.to_sym, value.to_s] }]
      CONFIGURATION_LIST.each do |opt|
        handle_error(:config_file_invalid) if @config[opt.to_sym].nil?
      end
    else
      handle_error :config_file_not_found
    end
    @config[:eb_bucket] = @config[:eb_bucket].to_s
    @config[:eb_key_prefix] = @config[:eb_key_prefix].to_s
    @config[:bundle_cache_bucket] = @config[:eb_bucket]
    @config[:bundle_cache_key_prefix] = @config[:eb_key_prefix] + '/bundle_cache/' + @command_opts[:stage]
    @config[:bundle_cache_key] = @config[:bundle_cache_key_prefix] + '/bundle_cache.tgz'
    @config[:saved_files_bucket] = @config[:eb_bucket]
    @config[:saved_files_key_prefix] = @config[:eb_key_prefix] + '/saved_files/' + @command_opts[:stage]
    @config[:source_bundle_bucket] = @config[:eb_bucket]
    @config[:source_bundle_key_prefix] = @config[:eb_key_prefix] + '/source_bundle'
    @config[:status_bucket] = @config[:eb_bucket]
    @config[:status_key_prefix] = @config[:eb_key_prefix] + '/status/' + @command_opts[:stage]
    @config[:status_key_last_version] = @config[:status_key_prefix] + '/LAST_VERSION'
    @config[:status_key_termination_protection] = @config[:status_key_prefix] + '/TERMINATION_PROTECTION'
  end
  
  def load_option_settings_file
    if File.exist?(APP_OPTION_SETTINGS_FILE)
      ['all', @command_opts[:stage]].each do |stage|
        settings = YAML.load_file(APP_OPTION_SETTINGS_FILE)[stage]
        settings.each do |namespace, namespace_settings|
          namespace_settings.each do |option_name, value|
            @option_settings << {:namespace => namespace.to_s, :option_name => option_name.to_s, :value => value.to_s}
          end if namespace_settings
        end if settings
      end
    end
    @option_settings += [{:namespace => 'aws:elasticbeanstalk:application:environment', :option_name => 'BUNDLE_CACHE_BUCKET', :value => @config[:bundle_cache_bucket]},
                         {:namespace => 'aws:elasticbeanstalk:application:environment', :option_name => 'BUNDLE_CACHE_KEY_PREFIX', :value => @config[:bundle_cache_key_prefix]},
                         {:namespace => 'aws:elasticbeanstalk:application:environment', :option_name => 'BUNDLE_CACHE_KEY', :value => @config[:bundle_cache_key]},
                         {:namespace => 'aws:elasticbeanstalk:application:environment', :option_name => 'SAVED_FILES_BUCKET', :value => @config[:saved_files_bucket]},
                         {:namespace => 'aws:elasticbeanstalk:application:environment', :option_name => 'SAVED_FILES_KEY_PREFIX', :value => @config[:saved_files_key_prefix]},
                         {:namespace => 'aws:elasticbeanstalk:application:environment', :option_name => 'STATUS_BUCKET', :value => @config[:status_bucket]},
                         {:namespace => 'aws:elasticbeanstalk:application:environment', :option_name => 'STATUS_KEY_PREFIX', :value => @config[:status_key_prefix]},
                         {:namespace => 'aws:elasticbeanstalk:application:environment', :option_name => 'STATUS_KEY_LAST_VERSION', :value => @config[:status_key_last_version]},
                         {:namespace => 'aws:elasticbeanstalk:application:environment', :option_name => 'STATUS_KEY_TERMINATION_PROTECTION', :value => @config[:status_key_termination_protection]}]
  end
  
  def parse_command_line_options
    begin
      OptionParser.new do |opts|
        opts.on('-s STAGE') do |value|
          @command_opts[:stage] = value
        end
        opts.on('-c COMMIT') do |value|
          @command_opts[:commit] = value
        end
        opts.on('-h') do
          Help.show_help
          exit
        end
        opts.on('-v') do
          Help.show_version
          exit
        end
        opts.on('--verbose') do
          $verbose = true
        end
      end.parse!
    rescue RuntimeError
      handle_error :bad_command_line_option
    end
    @command_opts[:task] = ARGV[0]
    handle_error(:bad_command_line_option) if (@command_opts[:stage].nil? || !Task.list.include?(@command_opts[:task]))
  end
  
  private
  
  # Helper Methods
  
  def handle_error(type, options={})
    Help.show_error(type, options)
    abort
  end
end
