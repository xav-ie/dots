# Safely and accurately update package-lock.json based on HEAD~
# Completely regenerating package-lock.json often leads to spurious errors.
def main [] {
  let has_conflicts = (git ls-files -u | lines | any {|line| $line =~ 'package.json' })

  if $has_conflicts {
    print $"⚠️ (ansi yellow)package.json has conflicts - skipping npm install(ansi reset)"
    exit 0
  }

  # Check if package.json was modified in this commit
  let package_changed = (git diff --name-only HEAD~ HEAD | lines | any {|file| $file == 'package.json' })

  if not $package_changed {
    print $"✅ (ansi green)package.json unchanged - skipping npm install(ansi reset)"
    exit 0
  }

  print $"📦 (ansi blue)package.json changed - regenerating package-lock.json...(ansi reset)"
  git checkout HEAD~ -- package-lock.json  # Reset lockfile to parent
  npm install
  git add package-lock.json
}
