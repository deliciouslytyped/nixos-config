#! /usr/bin/env nix-shell
#! nix-shell -p python3 -i python3
#TODO what about bootstrap though? this is precisely something that needs to be run when nix hasnt been bootstrapped yet...
import os
from sys import argv
from hashlib import sha256

args = lambda argv: tuple(map(lambda x: x.encode("ascii"), argv))

def search(argz, path, salt, target):
  for dirpath, dirnames, _ in os.walk(path):
    for n in dirnames:
      if sha256(salt + b"." + n).hexdigest().encode("ascii") == target:
        print(os.path.join(dirpath, n).decode("ascii"))

if len(argv) == 4:
  search(*args(argv))
elif len(argv) == 3:
  salted = b"%s.%s" % args(reversed(argv[1:3]))
  print(sha256(salted).hexdigest())
else:
  print("usage: %s (search_root salt target) | (target salt)" % argv[0])
