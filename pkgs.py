#!/usr/bin/python
"""Given a set H = {h_1, ... h_n} of n host names running a debian-based linux distribution,
this script outputs, for each host h_i, the set
P(h_i) \ [ P(h_1) ∩ ... ∩ P(h_n) ]
where P(h) denotes the set of packages installed on host h.
"""
import subprocess, sys, collections


def getPackages(host):
    pkgs = subprocess.check_output(["ssh", host, "dpkg -l | grep ^ii | cut -d' ' -f3"])
    return set(pkgs.splitlines())
if __name__ == "__main__":
    packages = collections.OrderedDict()
    for host in sys.argv[1:]:
        packages[host] = getPackages(host)
    commons = set.intersection(*packages.values())
    print(len(commons))
    for host, pkgs in packages.items():
        print("{} packages only on {}".format(len(pkgs - commons), host))
        print("\n".join("  " + p.decode('utf8') for p in  sorted(pkgs - commons)))
