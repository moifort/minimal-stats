# Registers the com.polyforms.stats identifier in the developer portal and
# creates its Mac App Store provisioning profile with the account's Apple
# Distribution certificate, then saves it. Dictate has Xcode do this
# (automatic signing); Stats has no Xcode project, so it goes through the API.
# Safe to run again: it reuses what exists.
#
#   ASC_KEY_ID=… ASC_ISSUER_ID=… ruby scripts/app-store/profile.rb [output]
#
# The output (default build/app-store/Stats.provisionprofile) is what
# scripts/build-app-store.sh reads from MAS_PROFILE, and, in base64, the
# MAS_PROVISION_PROFILE secret of the release workflow.
require_relative "asc"
require "fileutils"

output = ARGV.fetch(0, File.expand_path("../../build/app-store/Stats.provisionprofile", __dir__))
name = "Stats Mac App Store"

bundle = ASC.get("/v1/bundleIds?filter[identifier]=#{ASC::BUNDLE_ID}")["data"]
  .find { |b| b["attributes"]["identifier"] == ASC::BUNDLE_ID }
unless bundle
  _, created = ASC.request(:post, "/v1/bundleIds", { data: { type: "bundleIds",
    attributes: { identifier: ASC::BUNDLE_ID, name: "Stats", platform: "MAC_OS" } } })
  bundle = created["data"]
  puts "Identifier #{ASC::BUNDLE_ID} registered"
end

profile = ASC.get("/v1/profiles?filter[name]=#{URI.encode_www_form_component(name)}&filter[profileType]=MAC_APP_STORE")["data"]
  .find { |p| p["attributes"]["profileState"] == "ACTIVE" }
unless profile
  certificate = ASC.get("/v1/certificates?filter[certificateType]=DISTRIBUTION&limit=200")["data"]
    .max_by { |c| c["attributes"]["expirationDate"] } or abort("No Apple Distribution certificate on the account")
  _, created = ASC.request(:post, "/v1/profiles", { data: { type: "profiles",
    attributes: { name: name, profileType: "MAC_APP_STORE" },
    relationships: {
      bundleId: { data: { type: "bundleIds", id: bundle["id"] } },
      certificates: { data: [{ type: "certificates", id: certificate["id"] }] }
    } } })
  profile = created["data"]
  puts "Profile \"#{name}\" created"
end

FileUtils.mkdir_p(File.dirname(output))
File.binwrite(output, Base64.decode64(profile["attributes"]["profileContent"]))
puts "Saved #{output} (expires #{profile['attributes']['expirationDate']})"
