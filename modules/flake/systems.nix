# Build systems and debug toggle.
{ inputs, ... }:
{
  debug = true;
  systems = import inputs.systems;
}
