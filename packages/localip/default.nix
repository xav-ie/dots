{
  writeNuApplication,
}:
writeNuApplication {
  name = "localip";
  text = # nu
    ''
      # Run this and get your network-local ip-address.
      def main [] {
        match (uname | get kernel-name) {
          "Linux" => (ip -json route show default
                     | from json
                     | get 0
                     | get -i prefsrc src
                     | first)
          "Darwin" => (route -n get 192.0.2.1
                      | lines
                      | where ($it | str contains "interface:")
                      | split column -c ' '
                      | get column2
                      | first
                      | each {|it| ifconfig $it}
                      | lines
                      | where ($it | str contains "inet ")
                      | split column -c ' '
                      | get column2
                      | first)
        }
      }
    '';
}
