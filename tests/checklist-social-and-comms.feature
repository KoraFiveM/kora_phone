# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_phone-stevie — Social & Comms

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:open-phone @cat:social-and-comms
  Scenario: Open phone with M or /phone
    """
    Checklist test: With a phone item in inventory press M or run /phone; selected handset UI opens with prop and texting anim; close returns.
    """
    Given I have 1 "phone"
    When I press the "M" key
    Then I confirm: my selected handset UI opens with the phone prop and texting animation
    When I manually: close the phone
    Then I confirm: the phone UI closes and the prop and animation end
    When I run the command "/phone"
    Then I confirm: the selected handset UI opens again

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:phone-no-item @cat:social-and-comms
  Scenario: Opening without a phone
    """
    Checklist test: Remove all phone items and press M; phone does not open. Dead players cannot open it.
    """
    Given I have no "phone"
    When I press the "M" key
    Then I confirm: the phone does not open
    When I manually: get a phone item, die, then press M
    Then I confirm: the phone does not open while I am dead

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:handset-models @cat:social-and-comms
  Scenario: Three handset models
    """
    Checklist test: Use phone_standard, phone_flip, phone_fold items; each shows its own look (Orchard One, Circuit Flip, Atlas Fold). Legacy 'phone' acts as Standard.
    """
    Given I have 1 "phone"
    When I manually: obtain phone_standard, phone_flip and phone_fold items and use phone_standard
    Then I confirm: the phone shows the Orchard One look
    When I manually: use phone_flip
    Then I confirm: the phone shows the Circuit Flip look
    When I manually: use phone_fold
    Then I confirm: the phone shows the Atlas Fold look
    When I manually: remove the other handsets and use the legacy phone item
    Then I confirm: the legacy phone acts as the Standard model (Orchard One)

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:select-handset @cat:social-and-comms
  Scenario: Select between multiple handsets
    """
    Checklist test: Own two handsets; select the other in the handset panel; any active call ends and the selected phone changes.
    """
    Given I have 1 "phone"
    When I manually: obtain a second handset item so I own two handsets
    And I manually: ask a second player to call me and accept the call
    And I manually: open the handset panel and select the other handset
    Then I confirm: the active call ends
    And I confirm: the selected phone changes to the other handset

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:first-time-setup @cat:social-and-comms
  Scenario: First-time setup screen
    """
    Checklist test: Open a new phone; setup flow shows (appearance, PIN etc.). /phonereset [id] by moderator brings it back.
    """
    Given I have 1 "phone"
    When I manually: open a new phone for the first time
    Then I confirm: the setup flow shows (appearance, PIN etc.)
    When I manually: ask a moderator to run /phonereset with my id
    And I manually: open the phone again
    Then I confirm: the setup flow shows again

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:pin-lock @cat:social-and-comms
  Scenario: PIN lock and backup PIN
    """
    Checklist test: Settings > Privacy & security: set a PIN, close and reopen phone; PIN is required; wrong PIN is rejected.
    """
    Given I have 1 "phone"
    When I manually: open the phone and go to Settings > Privacy & security
    And I manually: set a PIN
    And I manually: close and reopen the phone
    Then I confirm: the phone asks for the PIN
    When I manually: enter a wrong PIN
    Then I confirm: the wrong PIN is rejected
    When I manually: enter the correct PIN
    Then I confirm: the phone unlocks

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:face-id @cat:social-and-comms
  Scenario: Simulated Face ID
    """
    Checklist test: Enrol Face ID in Privacy & security; reopening unlocks via character-based Face ID, backup PIN remains.
    """
    Given I have 1 "phone"
    When I manually: open Settings > Privacy & security and enrol Face ID
    And I manually: close and reopen the phone
    Then I confirm: the phone unlocks via character-based Face ID
    And I confirm: the backup PIN remains available in Privacy & security

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:contacts @cat:social-and-comms
  Scenario: Contacts app
    """
    Checklist test: Add, edit and delete a contact; contact is listed and used for calling/messaging.
    """
    Given I have 1 "phone"
    When I manually: open the phone and the Contacts app
    And I manually: add a contact
    Then I confirm: the contact is listed
    When I manually: edit the contact
    Then I confirm: the edit is saved and shown in the list
    When I manually: use the contact to start a call and to send a message
    Then I confirm: the contact is used for calling and messaging
    When I manually: delete the contact
    Then I confirm: the contact is no longer listed

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:calls-voice @cat:social-and-comms
  Scenario: Voice calls
    """
    Checklist test: Call another player's number; they get an incoming call, accept, talk via pma-voice, mute and hang up.
    """
    Given I have 1 "phone"
    When I manually: ask a second player to be ready with a phone and tell me their number
    And I manually: call the second player's number from my phone
    Then I confirm: the other player gets an incoming call
    When I manually: ask the second player to accept the call
    And I manually: talk to each other
    Then I confirm: both players hear each other via pma-voice
    When I manually: mute my microphone in the call
    Then I confirm: the other player no longer hears me
    When I manually: hang up
    Then I confirm: the call ends for both players

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:calls-video @cat:social-and-comms
  Scenario: Video calls upgrade
    """
    Checklist test: During a call upgrade to video; both players see WebRTC video; Flip closed pauses video, Fold fold/unfold moves display.
    """
    Given I have 1 "phone"
    When I manually: ask a second player to start a voice call with me and accept it
    And I manually: upgrade the call to video
    Then I confirm: both players see WebRTC video
    When I manually: close a Flip handset during the video call
    Then I confirm: the video pauses while the Flip is closed
    When I manually: fold and unfold a Fold handset during the video call
    Then I confirm: the display moves between folded and unfolded layouts

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:messages @cat:social-and-comms
  Scenario: Messages with photo attachments
    """
    Checklist test: Send texts and a photo attachment to another number; recipient gets notification sound and message in thread.
    """
    Given I have 1 "phone"
    When I manually: ask a second player for their number
    And I manually: open Messages and send a text to the other number
    And I manually: send a photo attachment to the same number
    Then I confirm: the other player gets a notification sound
    And I confirm: the other player sees the text and photo in the message thread

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:camera-gallery @cat:social-and-comms
  Scenario: Camera and Gallery
    """
    Checklist test: Open Camera, take rear and selfie photos (Alt aims, wheel zooms); photo saved to Gallery via screenshot-basic.
    """
    Given I have 1 "phone"
    When I manually: open the phone and the Camera app
    And I manually: take a rear photo, using Alt to aim and the mouse wheel to zoom
    And I manually: switch to selfie mode and take a selfie photo
    And I manually: open the Gallery app
    Then I confirm: both photos are saved in the Gallery

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:maps-gps @cat:social-and-comms
  Scenario: Maps / GPS app
    """
    Checklist test: Open Maps (gps) and set a waypoint or view map; works as launch app.
    """
    Given I have 1 "phone"
    When I manually: open the phone and the Maps (gps) app
    And I manually: set a waypoint or view the map
    Then I confirm: the map displays and the waypoint is set
    And I confirm: Maps works as a launch app

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:utility-apps @cat:social-and-comms
  Scenario: Mail, Notes, Weather, Calculator, Clock, Sound
    """
    Checklist test: Open each launch app and use it: write a note, calculate, check weather/clock, play music.
    """
    Given I have 1 "phone"
    When I manually: open the phone and the Mail app
    And I manually: open Notes and write a note
    Then I confirm: the note is saved
    When I manually: open Calculator and calculate 2+2
    Then I confirm: the calculator shows 4
    When I manually: open Weather and Clock
    Then I confirm: weather and clock display correctly
    When I manually: open Sound and play music
    Then I confirm: music plays
    And I confirm: each app opens as a launch app

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:mail-system @cat:social-and-comms
  Scenario: System mail and activity
    """
    Checklist test: Receive a system/job mail (e.g. via sendNewMailToOffline); Mail > Activity shows transaction notes; Accept action works once.
    """
    Given I have 1 "phone"
    When I use the "phone"
    And I manually: open the Mail app
    And I manually: receive a system or job mail for my character
    And I manually: open Mail > Activity
    Then I confirm: the system or job mail is received
    And I confirm: Mail > Activity shows transaction notes
    When I manually: press the Accept action on the mail
    And I manually: try pressing the Accept action again
    Then I confirm: the Accept action works only once

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:settings-hub @cat:social-and-comms
  Scenario: Settings sections
    """
    Checklist test: Settings shows Appearance, Connections, Cloud account, Privacy & security, Sound & alerts, About & resale; change theme/dark-light.
    """
    Given I have 1 "phone"
    When I use the "phone"
    And I manually: open the Settings app
    Then I confirm: Settings shows Appearance, Connections, Cloud account, Privacy & security, Sound & alerts and About & resale
    When I manually: change the theme between dark and light
    Then I confirm: the phone theme changes to match the selection

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:cloud-backup @cat:social-and-comms
  Scenario: Cloud backup and recovery code
    """
    Checklist test: Create a cloud account in Settings, back up, note the recovery code; restore on another handset.
    """
    Given I have 1 "phone"
    When I use the "phone"
    And I manually: open Settings > Cloud account and create a cloud account
    And I manually: back up the phone and note the recovery code
    Then I confirm: a recovery code is shown
    When I manually: restore the cloud account on another handset using the recovery code
    Then I confirm: contacts, messages, photos and preferences are restored on the other handset

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:sim-insert-remove @cat:social-and-comms
  Scenario: Insert and remove SIM
    """
    Checklist test: Settings > Connections: insert a phone_sim item (consumed into phone), see number; remove returns same SIM item.
    """
    Given I have 1 "phone"
    When I use the "phone"
    And I manually: open Settings > Connections and insert a phone_sim item from my inventory
    Then I confirm: the phone_sim item is consumed from my inventory
    And I confirm: the SIM number is shown in Connections
    When I manually: remove the SIM in Settings > Connections
    Then I confirm: the same phone_sim item (same number) returns to my inventory

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:sim-replacement @cat:social-and-comms
  Scenario: Replace a lost SIM
    """
    Checklist test: At a phone counter pay the replacement fee ($100); number kept and old SIM becomes invalid.
    """
    Given my cash balance is at least 500
    And I have 1 "phone"
    When I manually: go to a phone counter
    And I manually: pay the SIM replacement fee of $100
    Then my cash balance should have changed by -100
    And I confirm: my phone number is kept
    And I confirm: the old SIM is invalid

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:phone-shop-buy @cat:social-and-comms
  Scenario: Buy handsets and SIMs at Circuit Mobile
    """
    Checklist test: At a counter (e.g. Legion 127.4,-1029.2,29.4) buy Standard $1200, Flip $1800, Fold $2400 or SIM $100; works without owning a phone.
    """
    Given my cash balance is at least 5000
    And I have no "phone"
    When I manually: go to a Circuit Mobile counter (e.g. the Legion counter)
    And I manually: buy a Standard handset for $1200
    Then I confirm: I received a Standard handset and was charged $1200
    When I manually: buy a Flip handset for $1800
    Then I confirm: I received a Flip handset and was charged $1800
    When I manually: buy a Fold handset for $2400
    Then I confirm: I received a Fold handset and was charged $2400
    When I manually: buy a SIM for $100
    Then I confirm: I received a SIM and was charged $100
    And I confirm: all purchases worked without me owning a phone

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:phone-resale @cat:social-and-comms
  Scenario: Resell a handset
    """
    Checklist test: Remove SIM, factory reset unlocked, then sell back at shop for 50%; locked or SIM-installed phones are refused.
    """
    Given I have 1 "phone"
    When I manually: go to a Circuit Mobile shop counter
    And I manually: remove the SIM and factory reset the handset so it is unlocked
    And I manually: sell the handset back at the shop
    Then I confirm: I was paid 50% of the handset price
    When I manually: try to sell a locked handset
    Then I confirm: the sale is refused
    When I manually: try to sell a handset with a SIM installed
    Then I confirm: the sale is refused

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:account-recovery @cat:social-and-comms
  Scenario: Account recovery at shop
    """
    Checklist test: At a counter pay $500 recovery fee to recover a cloud account on a new handset.
    """
    Given my cash balance is at least 500
    And I have 1 "phone"
    When I manually: go to a Circuit Mobile counter
    And I manually: pay the $500 recovery fee to recover a cloud account on this new handset
    Then my cash balance should have changed by -500
    And I confirm: the cloud account is recovered on the new handset

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:workshop-counter @cat:social-and-comms
  Scenario: Mechanic-only Mobile Workshop
    """
    Checklist test: At workshop (-40.1,-1090.7,26.4) mechanics see the counter; other jobs do not.
    """
    Given my job is "mechanic"
    When I manually: go to the Mobile Workshop at -40.1,-1090.7,26.4
    Then I confirm: I can see the workshop counter as a mechanic
    When I manually: change to a non-mechanic job and return to the workshop
    Then I confirm: the counter is not visible with other jobs

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:wifi-hotspots @cat:social-and-comms
  Scenario: Public and private Wi-Fi
    """
    Checklist test: Near Legion public Wi-Fi (215.8,-810.1,30.7) connect in Settings; Workshop Private needs the password and mechanic owner.
    """
    Given I have 1 "phone"
    And I am at "legion_square"
    When I manually: go near the Legion public Wi-Fi hotspot
    And I use the "phone"
    And I manually: open Settings and connect to the public Wi-Fi
    Then I confirm: my phone connects to the public Wi-Fi
    When I manually: try to connect to Workshop Private without entering the password
    Then I confirm: the connection is refused without the password
    When I manually: try to connect to Workshop Private with the password while not being a mechanic owner
    Then I confirm: the connection is refused because I am not the mechanic owner
    When I manually: become the mechanic owner of the workshop, then connect to Workshop Private with the password
    Then I confirm: my phone connects to Workshop Private

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:phone-notifications @cat:social-and-comms
  Scenario: Notification sound and banners
    """
    Checklist test: Receive a text with phone closed; game text tone plays and banner shows; tapping opens Messages.
    """
    Given I have 1 "phone"
    When I manually: close the phone
    And I manually: ask a second player to send me a text
    Then I confirm: the game text tone plays
    And I confirm: a notification banner shows
    When I manually: tap the banner
    Then I confirm: the Messages app opens

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:phone-put-away @cat:social-and-comms
  Scenario: Phone prop/anim and put away
    """
    Checklist test: Open phone: prop in hand and anim; stand, drive, ragdoll or swim and check pose adapts; closing ends any call.
    """
    Given I have 1 "phone"
    When I use the "phone"
    Then I confirm: a phone prop is in my hand and the phone animation plays
    When I manually: stand, drive a vehicle, ragdoll and swim with the phone open
    Then I confirm: the phone pose adapts for each state
    When I manually: start a call and close the phone
    Then I confirm: closing the phone ends the call

  @kora_phone-stevie @checklist @checklist:kora_phone-stevie:phone-item-use @cat:social-and-comms
  Scenario: Use handset from inventory
    """
    Checklist test: Use a phone item from kora_inventory; selected handset opens (and binds a serial to that item).
    """
    Given I have 1 "phone"
    When I open my inventory
    And I use the "phone"
    Then I confirm: the selected handset opens
    And I confirm: a serial is bound to that phone item
