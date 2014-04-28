class Task
  INDENT_SPACING = 2
  PAGE_WIDTH = 100
  TASK_LIST = %w[deploy deploy_no_migrations clear_bundle_cache maintenance_on maintenance_off create_maintenance_version status restart reconfig rebuild recreate create terminate termination_protection_on termination_protection_off]
  
  def initialize(configuration)
    @command_opts = configuration.command_opts
    @config = configuration.config
    @option_settings = configuration.option_settings
    #
    @commit = {}
    @indent_level = 0
    @rails_migrate_db = true
    @status = {}
    @version = {}
    @versions = []
    @work_dir = Dir.mktmpdir
    # AWS
    AWS.config :access_key_id => configuration.aws_credential[:access_key_id], :secret_access_key => configuration.aws_credential[:secret_access_key]
    @eb = AWS::ElasticBeanstalk.new
    @eb_env = {}
    @eb_request_id = nil
    @s3 = AWS::S3.new
    # Show Information
    show_banner
    show_config_summary
    show_message
    if $verbose == true
      show_config_detail
      show_message
    end
  end
  
  def cleanup
    FileUtils.rm_rf @work_dir
  end
  
  # List of Primary Tasks
  
  def self.list
    TASK_LIST
  end
  
  # Primary Tasks
  
  # Deploy
  def deploy
    show_task_begin
    eb_env_info
    case
    when @eb_env[:status] != 'Ready'
      handle_error :eb_env_status_invalid
    else
      checkout_source_code
      create_eb_app_version
      eb_env_operation :eb_update_env_app_version
      record_last_version
      termination_protection_on
    end
    show_task_end
  end
  
  def deploy_no_migrations
    show_task_begin
    @rails_migrate_db = false
    deploy
    show_task_end
  end
  
  def clear_bundle_cache
    show_task_begin
    call_s3(:s3_delete, {:bucket => @config[:bundle_cache_bucket], :key => @config[:bundle_cache_key]})
    show_message "Bundle cache deleted"
    show_task_end
  end
  
  def maintenance_on
    show_task_begin
    eb_env_info
    case
    when @eb_env[:version_label] == 'maintenance'
      show_message "Already in maintenance mode"
      show_message "Nothing to do"
    when @versions.include?('maintenance') == false
      handle_error :maintenance_version_not_found
    when @eb_env[:status] != 'Ready'
      handle_error :eb_env_status_invalid
    else
      @version[:label] = 'maintenance'
      eb_env_operation :eb_update_env_app_version
    end
    show_task_end
  end
  
  def maintenance_off
    show_task_begin
    eb_env_info
    case
    when @eb_env[:version_label] != 'maintenance'
      show_message "Not in maintenance mode"
      show_message "Nothing to do"
    when @versions.include?(@status[:last_version]) == false || @status[:last_version].nil?
      handle_error :last_deployed_version_not_found
    when @eb_env[:status] != 'Ready'
      handle_error :eb_env_status_invalid
    else
      @version[:label] = @status[:last_version]
      eb_env_operation :eb_update_env_app_version
    end
    show_task_end
  end
  
  def create_maintenance_version
    show_task_begin
    create_eb_app
    checkout_source_code
    create_eb_app_version_maintenance
    show_task_end
  end
  
  # Manage
  def status
    show_task_begin
    eb_env_info
    show_task_end
  end
  
  def restart
    show_task_begin
    eb_env_info
    case
    when @eb_env[:status] != 'Ready'
      handle_error :eb_env_status_invalid
    else
      eb_env_operation :eb_restart_app_server
    end
    show_task_end
  end
  
  def reconfig
    show_task_begin
    eb_env_info
    case
    when @eb_env[:status] != 'Ready'
      handle_error :eb_env_status_invalid
    else
      eb_env_operation :eb_update_env_config
    end
    show_task_end
  end
  
  def rebuild
    show_task_begin
    eb_env_info
    case
    when @status[:termination_protection] != false
      handle_error :termination_protection_on
    when @eb_env[:status] != 'Ready'
      handle_error :eb_env_status_invalid
    else
      eb_env_operation :eb_rebuild_env
      restart
      termination_protection_on
    end
    show_task_end
  end
  
  def recreate
    show_task_begin
    terminate
    create
    show_task_end
  end
  
  def create
    show_task_begin
    eb_env_info
    case
    when @eb_env[:status] != nil
      show_message "EB environment already created"
      show_message "Nothing to do"
    else
      create_eb_app
      create_eb_app_version_default
      checkout_source_code
      create_eb_app_version_maintenance
      @versions = call_eb(:eb_describe_app_versions).collect { |hsh| hsh[:version_label] }
      @version[:label] = (@versions.include?('maintenance') ? 'maintenance' : 'default')
      eb_env_operation :eb_create_env
      termination_protection_on
    end
    show_task_end
  end
  
  def terminate
    show_task_begin
    eb_env_info
    case
    when @status[:termination_protection] != false
      handle_error :termination_protection_on
    when @eb_env[:status].nil?
      show_message "The EB environment does not currently exist"
      show_message "Nothing to do"
    when @eb_env[:status] != 'Ready'
      handle_error :eb_env_status_invalid
    else
      eb_env_operation :eb_terminate_env, :end_status => 'Terminated'
      clear_status
    end
    show_task_end
  end
  
  def termination_protection_on
    show_task_begin
    call_s3(:s3_write, {:bucket => @config[:status_bucket], :key => @config[:status_key_termination_protection], :string => 'true'})
    show_message "TERMINATION_PROTECTION = '#{call_s3(:s3_read, {:bucket => @config[:status_bucket], :key => @config[:status_key_termination_protection]})}'"
    show_task_end
  end
  
  def termination_protection_off
    show_task_begin
    call_s3(:s3_write, {:bucket => @config[:status_bucket], :key => @config[:status_key_termination_protection], :string => 'false'})
    show_message "TERMINATION_PROTECTION = '#{call_s3(:s3_read, {:bucket => @config[:status_bucket], :key => @config[:status_key_termination_protection]})}'"
    show_task_end
  end
  
  private
  
  # Secondary Tasks
  
  def add_bundle_cache
    show_task_begin
    if call_s3(:s3_read_file, {:bucket => @config[:bundle_cache_bucket], :key => @config[:bundle_cache_key], :file => File.join(@work_dir, 'bundle_cache.tgz')})
      show_message "Bundle cache downloaded from S3:"
      show_message "@ #{@config[:bundle_cache_bucket]}/#{@config[:bundle_cache_key]}"
      run_shell "rm -rf vendor/bundle ; tar -xzf bundle_cache.tgz ; rm -f bundle_cache.tgz", @work_dir
      show_message "Bundle cache inserted into source bundle"
    else
      show_message "Bundle cache not found"
    end
    show_task_end
  end
  
  def checkout_source_code
    show_task_begin
    git_tree = @command_opts[:commit] || 'master'
    @commit[:code] = run_shell("git rev-parse #{git_tree}", APP_ROOT).strip[0,7]
    @commit[:message] = run_shell("git show -s --format=%s #{git_tree}", APP_ROOT).strip[0,60]
    run_shell "git archive --format=tar #{git_tree} | (cd #{@work_dir} && tar -xpf -)", APP_ROOT
    show_message "Git Commit Code = #{@commit[:code]}"
    show_message "Git Commit Message = #{@commit[:message]}"
    show_task_end
  end
  
  def clear_status
    show_task_begin
    call_s3(:s3_delete, {:bucket => @config[:status_bucket], :key => @config[:status_key_last_version]})
    call_s3(:s3_delete, {:bucket => @config[:status_bucket], :key => @config[:status_key_termination_protection]})
    show_message "Deleted status flags"
    show_task_end
  end
  
  def create_eb_app
    show_task_begin
    apps = call_eb(:eb_describe_apps).collect { |hsh| hsh[:application_name] }
    if apps.include?(@config[:app])
      show_message "Application '#{@config[:app]}' already created"
    else
      call_eb(:eb_create_app)
      show_message "Application '#{@config[:app]}' created"
    end
    show_task_end
  end
  
  def create_eb_app_version
    show_task_begin
    @version[:label] = "#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}-#{@commit[:code]}"
    @version[:description] = "[#{@commit[:code]}] #{@commit[:message]}"
    @version[:bucket] = @config[:source_bundle_bucket]
    @version[:key] = "#{@config[:source_bundle_key_prefix]}/#{@version[:label]}.zip"
    prepare_source_code
    add_bundle_cache
    run_shell "zip -r #{@version[:label]} .", @work_dir
    call_s3 :s3_write_file, {:bucket => @version[:bucket], :key => @version[:key], :file => File.join(@work_dir, @version[:label] + '.zip')}
    show_message "Source bundle uploaded to S3:"
    show_message "@ #{@version[:bucket]}/#{@version[:key]}"
    call_eb :eb_create_app_version
    show_message "Application version '#{@version[:label]}' created"
    show_task_end
  end
  
  def create_eb_app_version_default
    show_task_begin
    @version[:label] = 'default'
    @version[:description] = 'Default'
    @version[:bucket] = 'elasticbeanstalk-samples-us-east-1'
    @version[:key] = 'ruby-secondsample.zip'
    case
    when @versions.include?(@version[:label])
      show_message "Application version '#{@version[:label]}' already created"
    else
      call_eb :eb_create_app_version
      show_message "Application version '#{@version[:label]}' created"
    end
    show_task_end
  end
  
  def create_eb_app_version_maintenance
    show_task_begin
    @version[:label] = 'maintenance'
    @version[:description] = 'Maintenance'
    @version[:bucket] = @config[:source_bundle_bucket]
    @version[:key] = "#{@config[:source_bundle_key_prefix]}/#{@version[:label]}.zip"
    maintenance_source_dir = File.join(@work_dir, 'vendor', 'maintenance')
    if File.directory?(maintenance_source_dir)
      @versions = call_eb(:eb_describe_app_versions).collect { |hsh| hsh[:version_label] }
      call_eb(:eb_delete_app_version) if @versions.include?(@version[:label])
      run_shell "zip -r #{@version[:label]} .", maintenance_source_dir
      call_s3 :s3_write_file, {:bucket => @version[:bucket], :key => @version[:key], :file => File.join(maintenance_source_dir, @version[:label] + '.zip')}
      show_message "Source bundle uploaded to S3:"
      show_message "@ #{@version[:bucket]}/#{@version[:key]}"
      call_eb :eb_create_app_version
      show_message "Application version '#{@version[:label]}' created"
    else
      show_message "Maintenance source directory not found"
      show_message "Cannot create maintenance version"
    end
    show_task_end
  end
  
  def eb_env_info
    show_task_begin
    @eb_env = call_eb :eb_describe_env_by_name
    @versions = call_eb(:eb_describe_app_versions).collect { |hsh| hsh[:version_label] }
    @status[:last_version] = call_s3(:s3_read, {:bucket => @config[:status_bucket], :key => @config[:status_key_last_version]})
    @status[:last_version].chomp! unless @status[:last_version].nil?
    @status[:termination_protection] = call_s3(:s3_read, {:bucket => @config[:status_bucket], :key => @config[:status_key_termination_protection]})
    @status[:termination_protection].chomp! unless @status[:termination_protection].nil?
    @status[:termination_protection] = (@status[:termination_protection] == 'false' ? false : true)
    show_message ":::::"
    show_message "EB Environment Information:"
    show_message "EB Environment ID = #{@eb_env[:environment_id] || 'NA'}"
    show_message "EB Environment Name = #{@eb_env[:environment_name] || 'NA'}"
    show_message "EB Environment Status = #{@eb_env[:status] || 'NA'}"
    show_message "EB Environment Version = #{@eb_env[:version_label] || 'NA'}"
    case @eb_env[:status]
    when 'Launching', 'Terminating', 'Updating'
      show_message "EB is still working on a previous operation (busy)"
    when nil
      show_message "EB environment does not currently exist (needs to be created)"
    end
    show_message "Last deployed application version is '#{@status[:last_version] || 'NA'}'"
    show_message "Termination Protection is #{@status[:termination_protection] ? 'ON' : 'OFF'}"
    show_message ":::::"
    show_task_end
  end
  
  def eb_env_operation(operation, options={})
    show_task_begin
    show_message "EB Operation = #{operation}"
    @eb_request_id = call_eb(operation)[:response_metadata][:request_id]
    if @eb_request_id
      # Show Progress
      status = nil
      end_status = options[:end_status] || 'Ready'
      time = 0
      show_message "Request ID = #{@eb_request_id}"
      show_message "The EB operation is in progress:"
      while status != end_status do
        status = (@eb_env[:environment_id] ? call_eb(:eb_describe_env_by_id)[:status] : call_eb(:eb_describe_env_by_name)[:status])
        show_message "* Elapsed Time = #{time} sec"
        sleep 10
        time += 10
      end
      show_message "EB operation completed"
      # Show Events
      show_message "EB operation output:"
      events = call_eb(:eb_describe_events)[:events]
      events.sort_by { |hsh| hsh[:event_date] }.each do |event|
        show_message "* #{event[:message]}"
      end
    else
      handle_error :aws_api
    end
    show_task_end
  end
  
  def prepare_source_code
    show_task_begin
    run_shell "echo #{@commit[:code]} > COMMIT ; echo #{@version[:label]} > VERSION", @work_dir
    show_message "Recorded commit and version information"
    if @rails_migrate_db == false
      run_shell "sed '/RAILS_MIGRATE_DB/,/$/ s/true/false/' .ebextensions/01_options.config > .ebextensions/01_options.config.tmp", @work_dir
      run_shell "mv -f .ebextensions/01_options.config.tmp .ebextensions/01_options.config", @work_dir
      show_message "EB instance envvar 'RAILS_MIGRATE_DB' will be set to 'false'"
    end
    show_task_end
  end
  
  def record_last_version
    show_task_begin
    call_s3(:s3_write, {:bucket => @config[:status_bucket], :key => @config[:status_key_last_version], :string => @version[:label]})
    show_message "LAST_VERSION = '#{call_s3(:s3_read, {:bucket => @config[:status_bucket], :key => @config[:status_key_last_version]})}'"
    show_task_end
  end
  
  def run_shell(command, cwd='.')
    show_task_begin if $verbose == true
    command = "cd #{cwd} ; #{command} 2>&1"
    show_message "\"#{command}\"" if $verbose == true
    output = %x[#{command}]
    handle_error(:shell_command, {:command => command, :debug => output}) if $?.exitstatus != 0
    show_task_end if $verbose == true
    output
  end
  
  # Helper Methods
  
  def call_eb(eb_operation)
    send(eb_operation)
  rescue Exception => error
    handle_error :aws_api, :debug => error.message
  end
  
  def call_s3(s3_operation, s3_options)
    send(s3_operation, s3_options)
  rescue Exception => error
    handle_error :aws_api, :debug => error.message
  end
  
  def handle_error(type, options={})
    Help.show_error(type, options)
    cleanup
    abort
  end
  
  def show_banner
    show_message
    show_message
    show_message "===================================================================================================="
    show_message " EB Manager"
    show_message "===================================================================================================="
    show_message
  end
  
  def show_config_detail
    show_message "Configuration Detail:"
    show_message
    show_message "Command Line Options:"
    @command_opts.keys.sort_by { |key| key.to_s }.each { |key| show_message "#{key} = #{@command_opts[key]}" }
    show_message
    show_message "Configuration File Options:"
    @config.keys.sort_by { |key| key.to_s }.each { |key| show_message "#{key} = #{@config[key]}" }
    show_message
    show_message "EB Environment Options:"
    options = []
    @option_settings.each { |hsh| options << "#{hsh[:namespace]} '#{hsh[:option_name]}' '#{hsh[:value]}'" }
    options.sort.each { |option| show_message(option) }
  end
  
  def show_config_summary
    show_message "Configuration Summary:"
    show_message "Application = #{@config[:app]}"
    show_message "Stage = #{@command_opts[:stage]}"
    show_message "EB Environment Name = #{@config[:env]}"
  end
  
  def show_message(message=' ')
    indent = @indent_level * INDENT_SPACING
    message.split(/(.{#{PAGE_WIDTH - indent}})/).each { |line| print(' ' * indent, line, "\n") if !line.empty? }
    STDOUT.flush
  end
  
  def show_task_begin
    caller[0] =~ /`(.*?)'/
    show_message "Running '#{$1}'"
    @indent_level += 1
  end
  
  def show_task_end
    @indent_level -= 1
    caller[0] =~ /`(.*?)'/
    show_message "Completed '#{$1}'"
  end
  
  # AWS API Operations
  
  def eb_create_app
    @eb.client.create_application(:application_name => @config[:app])
  end
  
  def eb_create_app_version
    @eb.client.create_application_version(:application_name => @config[:app],
                                          :version_label => @version[:label],
                                          :description => @version[:description],
                                          :source_bundle => {:s3_bucket => @version[:bucket],
                                                             :s3_key => @version[:key]})
  end
  
  def eb_create_env
    @eb.client.create_environment(:application_name => @config[:app],
                                  :version_label => @version[:label],
                                  :environment_name => @config[:env],
                                  :solution_stack_name => @config[:solution_stack],
                                  :cname_prefix => @config[:cname_prefix],
                                  :option_settings => @option_settings)
  end
  
  def eb_delete_app_version
    @eb.client.delete_application_version(:application_name => @config[:app], :version_label => @version[:label], :delete_source_bundle => true)
  end
  
  def eb_describe_apps
    @eb.client.describe_applications[:applications]
  end
  
  def eb_describe_app_versions
    @config[:app] ? @eb.client.describe_application_versions(:application_name => @config[:app])[:application_versions] : []
  end
  
  def eb_describe_env_by_id
    @eb_env[:environment_id] ? Hash[*@eb.client.describe_environments(:environment_ids => [@eb_env[:environment_id]], :include_deleted => true)[:environments]] : {}
  end
  
  def eb_describe_env_by_name
    @config[:env] ? Hash[*@eb.client.describe_environments(:environment_names => [@config[:env]], :include_deleted => false)[:environments]] : {}
  end
  
  def eb_describe_events
    @eb_request_id ? @eb.client.describe_events(:request_id => @eb_request_id) : {}
  end
  
  def eb_rebuild_env
    @eb.client.rebuild_environment(:environment_id => @eb_env[:environment_id])
  end
  
  def eb_restart_app_server
    @eb.client.restart_app_server(:environment_id => @eb_env[:environment_id])
  end
  
  def eb_terminate_env
    @eb.client.terminate_environment(:environment_id => @eb_env[:environment_id])
  end
  
  def eb_update_env_app_version
    @eb.client.update_environment(:environment_id => @eb_env[:environment_id], :version_label => @version[:label])
  end
  
  def eb_update_env_config
    @eb.client.update_environment(:environment_id => @eb_env[:environment_id], :option_settings => @option_settings)
  end
  
  def s3_delete(options)
    obj = @s3.buckets[options[:bucket]].objects[options[:key]]
    obj.delete if obj.exists?
  end
  
  def s3_read(options)
    obj = @s3.buckets[options[:bucket]].objects[options[:key]]
    obj.exists? ? obj.read : nil
  end
  
  def s3_read_file(options)
    obj = @s3.buckets[options[:bucket]].objects[options[:key]]
    if obj.exists?
      File.open(Pathname.new(options[:file]), 'w') do |file|
        obj.read do |chunk|
          file.write(chunk)
        end
      end
      return true
    else
      return false
    end
  end
  
  def s3_write(options)
    obj = @s3.buckets[options[:bucket]].objects[options[:key]]
    obj.write(options[:string])
  end
  
  def s3_write_file(options)
    obj = @s3.buckets[options[:bucket]].objects[options[:key]]
    obj.write(Pathname.new(options[:file]))
  rescue
    show_message "Warning: S3 error, will retry once in 20 seconds"
    sleep 20
    obj = @s3.buckets[options[:bucket]].objects[options[:key]]
    obj.write(Pathname.new(options[:file]))
  end
end
