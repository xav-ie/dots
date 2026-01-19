#!/usr/bin/env -S nu --stdin

def main [] {
  format-staged
  lint-staged --fix
}
