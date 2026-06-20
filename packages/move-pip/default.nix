{
  writeScriptBin,
}:
writeScriptBin "move-pip" (builtins.readFile ./move-pip.js)
