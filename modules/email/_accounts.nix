# Shared email account definitions, consumed by ./nixos.nix and ./home.nix.
{
  accounts = [
    {
      name = "work";
      secretsId = "account1";
      default = true;
    }
    {
      name = "personal";
      secretsId = "account2";
      default = false;
    }
  ];
  # Canonical folder list shared by tmpfiles rules, isync channels, and himalaya aliases.
  # gmailRemote is the IMAP path on Gmail's side.
  folders = [
    {
      name = "inbox";
      gmailRemote = "INBOX";
    }
    {
      name = "sent";
      gmailRemote = "[Gmail]/Sent Mail";
    }
    {
      name = "drafts";
      gmailRemote = "[Gmail]/Drafts";
    }
    {
      name = "trash";
      gmailRemote = "[Gmail]/Trash";
    }
    {
      name = "archive";
      gmailRemote = "[Gmail]/All Mail";
    }
    {
      name = "spam";
      gmailRemote = "[Gmail]/Spam";
    }
  ];
}
