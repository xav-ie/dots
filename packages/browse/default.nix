{
  openssh,
  ssh-client-host,
  xdg-utils,
  writeNuApplication,
}:
writeNuApplication {
  name = "browse";
  runtimeInputs = [
    openssh
    ssh-client-host
    xdg-utils
  ];
  text = # nu
    ''
      # Open a URL in *my* browser. Under a remote session the browser lives
      # on the laptop I attached from, so ssh back and `open` it there;
      # otherwise open it locally.
      def main [url: string] {
        let host = (ssh-client-host)
        if ($host | is-empty) { ^xdg-open $url } else { ^ssh $host open $url }
      }
    '';
}
