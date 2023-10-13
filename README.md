# My NixOS

Right now, I only run this on my desktop, but I hope to get this config to my other machines

## Usage

Check the Makefile!

## Things to work on

-  Make it cross-system compatible ... there are some resources and other configs that do this 
-  Move everything from [/home/x/.config/.md](#homexconfigmd) into home-manager. If my dot-files were immutable, then random-ass programs would not be able to mess with and edit them, which happened more times than you would think :/
-  SECRETS - right now, I am thinking of using `pass` or `age` to just store all my ENV variables, but then it is another master password to remember, so I think I would rather figure something out with the bitwarden cli, my manager of choice. Honestly, I don't really know the best course of action, because what if I want to change my manager?? I might also want to just completely forgo bitwarden and just use good old encryption... There has to be someone else who thought of this
    -  Resarch secret solutions others have worked on.
-  Lights, I want my lights to be fully controlled from my computer:
    - Computer lights are semi-controllable through `open-rgb -p`, but I need to set up more profiles. 
    - Govee light is controlled via an API. I think I just have to build a simple script to do so.
    - Apple Home / TP-Link Switches.. I have no idea how to connect to these yet, but I do know it is annoying to open my phone to turn on my lights... I probably need to buy a homepod mini to also make them "always connected" bc my phone takes like 10-20 seconds to connect to them when I get home, which is really annoying bc it also sometimes does not connect.
-  Waybar replacement - I think I might go with EWW... They are actual windows that can be spawned, meaning native wayland effects and borders can be applied to them. To my understanding, Waybar uses a gtk-layer-shell, which is:
      1. Difficult to blur: Most compositors would have to blur the entire bar where there are transparent pixels. Hyprland has feature to avoid blurring transparent pixels, but it is still not very good
      2. Not focusable via keyboard?I just know if EWW spawns native windows, Waybar does not, which means that I cant easily access the separate parts with my keyboard
-  Global mute - this will require building a virtual HID device that is recognized by Zoom. Then, when you mute this virtual device, the state is reflected in Zoom as well. This opens up many possibilities, the most obvious being a notification tray icon you can use to easily see muted state
-  Hardware acceleration - Zoom only works on chromium on my computer, which does not have acceleration. Zoom kind of works on firefox, but then firefox zoom has a memory leak and it eats all of my ram. 
-  Qutebrowser screenshare - for some reason, Qutebrowser does not appear to be using xdg-desktop-portal-wlr for screensharing... idk what that is about. Here are some resources to diagnose:
    - https://github.com/emersion/xdg-desktop-portal-wlr/wiki/%22It-doesn't-work%22-Troubleshooting-Checklist
    - https://gitlab.com/jokeyrhyme/dotfiles/-/blob/main/usr/local/bin/dotfiles-sway.sh
    - https://soyuka.me/make-screen-sharing-wayland-sway-work/
-  Better fonts: overall, the fonts could be a lot better
-  Backgrounds repo/drive sync: I need to sync my backgrounds with proton drive.
-  Email notifications - web browser email notifications are acceptable, but they do not have a "delete" nor a "mark as read action", which would really help me to get to inbox 0. 
-  PETS - I really want to modify Spamton-Linux-Shimejii repo to have multiple different types of Shimejii. Right now, there is just this really ugly one. I also want to fix the divide by zero errors that keep making it crash.
-  Transparent Qutebrowser. Qutebrowser actually works well enough already for transparent, or mostly transparent web backgrounds. There are a couple of things that need to happen first:
    - File issue and begin work on drawing hints on top of webpage with slight transparency - As soon as you set webpage.bg to be slightly transparent, the qutebrowser seems to draw things under where they should be, and I am not sure why. First, document the anomalies then begin work on them
    - Write a simple greasemonkey script to apply these transparency modifications to my favorite websites
    - Qutebrowser has a final issue of tabs while switching resizing the webpage. I am not sure who would actually want that to happen... It should be drawn as an overlay on top of the webpage itself...

-  File browser - I have no good terminal file browser 😭 ... my LF uses some ueberzug alternative in go that always crashes and stays crashed... even on restart. I need to find an excellent terminal file browser preview
-  RSS - I have a lot of blogs bookmarked in Firefox, but no way to really view them
-  Email - just set up himalaya email client in vim.
-  Reminders - I want my gcal to appear in my system and I want to be able to easily manage past and future reminders, a calendar. So I just have to set up a good and pretty system calendar
-  Pomodoro - Set up system pomodoro
-  Time tracking - It would be nice to get analytics of how I spend my time and what I did for that day, I think this would mostly be a qutebrowser extension + a thin launcher client in Rofi / Kitty to monitor all launched programs. 
-  Screenshots/recording - wf-recorder is ... fine. I would prefer somebindings and a bit more chrome/indicators in my bar to show that I am recording screen. I dislike that I could be screensharing and not really be aware that I am.
-  DND - I would like to trigger DND when I am scrensharing. I really dislike that notifications come through on screenshare. Maybe I can still allow notifications, but hide them from screenshare entirely??? That would be really cool.

-  CONSOOM - PIP in Qutebrowser lowkey sucks. It does not have PIP support. The suggested workaround is to use MPV. This has a few problems. 
      1. Videos do not show as watched on youtube - what I do right now is set the quality to 144p and mute and just let it play in background
      2. MPV does not autochange the yt-dlp source as I resize MPV. When MPV is really smol, the source url from YT is always really high quality which is wasteful and causes weird artifacts
      3. I want better snapping of PIP windows. Ideally, the PIP behaves exactly like MacOS Arc PIP works. It anchors the PIP to some corner and resizing happens from that corner alone. 
      4. I also just need to figure out binding to make this mostly happen automatically for already open video, I have "M" binding to open video link on page, but not current page itself.



