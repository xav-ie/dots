# Check if the current session is accessed via SSH
def main [] {
  who -u | str contains "pts"
}
