module Help
  ERRORS = {:aws_api => ["The AWS API operation failed"],
            :aws_credential_file_envvar_not_set => ["Environment variable 'AWS_CREDENTIAL_FILE' is not set"],
            :aws_credential_file_invalid => ["The AWS Credential File is not in a valid format"],
            :aws_credential_file_not_found => ["The AWS Credential File cannot be found"],
            :bad_command_line_option => ["You have specified an invalid command line option(s) and/or task",
                                         "For help, use 'ebm -h'"],
            :config_file_invalid => ["The configuration file '.ebm/config.yml' is missing one or more required options",
                                     "For a list of mandatory configuration options, use 'ebm -h'"],
            :config_file_not_found => ["The required configuration file '.ebm/config.yml' cannot be found"],
            :eb_env_status_invalid => ["The Elastic Beanstalk environment is not in a valid state for this operation"],
            :last_deployed_version_not_found => ["The last deployed application version cannot be found or determined",
                                                 "Deploy again to recover"],
            :maintenance_version_not_found => ["The maintenance application version cannot be found",
                                               "Create one first"],
            :shell_command => ["A problem was encountered while executing the following shell command"],
            :termination_protection_on => ["Termination protection is on",
                                           "Turn it off first"]}
  
  def self.show_error(type, options={})
    print "\n"
    print "***Error:\n"
    ERRORS[type].each { |line| print line, "\n" }
    print "\n"
    case type
    when :aws_api
      print "Debug:\n"
      print "#{options[:debug]}\n\n"
    when :shell_command
      print "Command:\n"
      print "#{options[:command]}\n\n"
      print "Debug:\n"
      print "#{options[:debug]}\n\n"
    end
  end
  
  def self.show_help
    print "\n"
    print "Usage:\n"
    print "ebm -s STAGE [-c COMMIT] [--verbose] TASK\n"
    print "ebm -h (show this Help message and exit)\n"
    print "ebm -v (show program Version and exit)\n\n"
    print "Tasks:\n"
    print "#{Task.list.join("\n")}\n\n"
    print "Examples:\n"
    print "ebm -s production deploy\n"
    print "ebm -s staging -c 3def867 deploy_no_migrations\n"
    print "ebm -s production --verbose restart\n\n"
    print "Configuration Files:\n"
    print "APP_GIT_ROOT/.ebm/config.yml (required)\n"
    print "APP_GIT_ROOT/.ebm/optionsettings.yml (optional)\n\n"
    print "Required 'config.yml' Options:\n"
    print "#{Configuration.list.join(' ')}\n\n"
    print "Remarks:\n"
    print "* You need to be in the app's Git repository's root directory when invoking 'ebm'\n"
    print "* COMMIT defaults to HEAD of master of the Git repository if unspecified\n"
    print "* Make sure your local Git repository is up-to-date before using ebm\n\n"
  end
  
  def self.show_version
    print "\n"
    print "EB Manager version #{EBM_VERSION}\n"
  end
end
