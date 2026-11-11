# Sets the App Review information of the editable macOS version: the contact
# is copied from another app of the account (Shiori), as for Dictate, and the
# notes explain what Stats does in the sandbox.
#
#   ASC_KEY_ID=… ASC_ISSUER_ID=… ruby scripts/app-store/review.rb
require_relative "asc"

NOTES = <<~TEXT.strip
  Stats is a menu bar system monitor. It has no window and no Dock icon: it lives in the menu bar as four small charts, from left to right CPU, network (download below, upload above), memory and disk.

  To test: launch Stats, look at the four charts at the right of the menu bar, then click them to open the popover with the live figures and the apps that used the network over the last five minutes. Right-click (or Control-click) the charts for "Open at Login" and "Quit Stats". Stats only opens at login once the user turns it on there.

  Sandbox and network: Stats sends and receives nothing itself. The per-app network list comes from /usr/bin/nettop, which the app runs every 10 seconds; nettop inherits the sandbox and reads the system's network statistics through a socket, which the sandbox only allows with com.apple.security.network.client. That is the only reason for this entitlement.

  No account, no login, no data collected.
TEXT

app = ASC.get("/v1/apps?filter[bundleId]=#{ASC::BUNDLE_ID}")["data"].first or abort("No Stats app")
version = ASC.get("/v1/apps/#{app['id']}/appStoreVersions?filter[platform]=MAC_OS")["data"]
  .find { |v| %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED].include?(v["attributes"]["appStoreState"]) } or abort("No editable version")

source = ASC.get("/v1/apps?filter[bundleId]=com.polyforms.shiori.app")["data"].first or abort("No Shiori app to copy the contact from")
source_version = ASC.get("/v1/apps/#{source['id']}/appStoreVersions?limit=1")["data"].first
contact = ASC.get("/v1/appStoreVersions/#{source_version['id']}/appStoreReviewDetail")["data"]["attributes"]
  .slice("contactFirstName", "contactLastName", "contactEmail", "contactPhone")

attributes = contact.merge("notes" => NOTES, "demoAccountRequired" => false)
_, existing = ASC.request(:get, "/v1/appStoreVersions/#{version['id']}/appStoreReviewDetail", nil, [404])
if (id = existing.dig("data", "id"))
  ASC.request(:patch, "/v1/appStoreReviewDetails/#{id}", { data: { type: "appStoreReviewDetails", id: id, attributes: attributes } })
else
  ASC.request(:post, "/v1/appStoreReviewDetails", { data: { type: "appStoreReviewDetails", attributes: attributes,
    relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: version["id"] } } } } })
end
puts "Review information set"
