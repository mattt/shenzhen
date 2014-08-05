$:.push File.expand_path('../', __FILE__)

require 'plugins/testflight'
require 'plugins/hockeyapp'
require 'plugins/deploygate'
require 'plugins/ftp'
require 'plugins/s3'
require 'plugins/itunesconnect'

require 'commands/build'
require 'commands/distribute'
require 'commands/info'
