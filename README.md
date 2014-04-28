EB Manager
==========

EB Manager (or EBM) is a small Ruby app to manage the entire lifecycle of an AWS Elastic Beanstalk application from
initial creation through routine version updates through eventual termination.  EBM uses the AWS Ruby SDK to make API
calls to AWS.


Installation
============

Pre-requisites:
• Ruby 1.8.7 or 1.9
• Ruby Gem 'aws-sdk' 1.8.0 or later
• Command line binaries git, sed, tar & zip


Configuration
=============

EB Manager reads from the following 2 configuration files:
• .ebm/config.yml (required)
• .ebm/optionsettings.yml (optional)

Both are located within and specified relative to the root directory of the Elastic Beanstalk hosted application
that you would like to deploy or manage. Together, they define the Elastic Beanstalk environment for the
application and the AWS resources required.

In addition, EB Manager expects to find the standard AWS Credential File, specifying the AWS API Access Key ID
and Secret Key.  The environment variable 'AWS_CREDENTIAL_FILE', pointing to the location of the AWS Credential
File must be set.


Usage
=====

To use EB Manager, first change into the application's Git repository's root directory, and then invoke the
command 'ebm' with the appropriate options.

$ cd app_git_root_directory
$ ebm -s production deploy

For a help page to guide you further:

$ ebm -h
