#!/usr/bin/env ruby

require "spaceship"

operation = ENV.fetch("APPLE_PHASED_OPERATION")
version_string = ENV.fetch("APP_VERSION")
bundle_id = ENV.fetch("APP_BUNDLE_ID", "com.synaplan.app")

token = Spaceship::ConnectAPI::Token.create(
  key_id: ENV.fetch("APP_STORE_CONNECT_KEY_ID"),
  issuer_id: ENV.fetch("APP_STORE_CONNECT_ISSUER_ID"),
  filepath: ENV.fetch("APP_STORE_CONNECT_KEY_FILE")
)
Spaceship::ConnectAPI.token = token

app = Spaceship::ConnectAPI::App.find(bundle_id)
abort("App not found for #{bundle_id}") unless app

version = app
  .get_app_store_versions(filter: { platform: Spaceship::ConnectAPI::Platform::IOS })
  .find { |candidate| candidate.version_string == version_string }
abort("App Store version #{version_string} not found") unless version

phased_release = version.fetch_app_store_version_phased_release
abort("Phased release for #{version_string} not found") unless phased_release

case operation
when "pause", "rollback"
  phased_release.pause
when "resume"
  phased_release.resume
else
  abort("Unsupported phased-release operation: #{operation}")
end

puts("Apple phased release #{operation} completed for #{version_string}")
