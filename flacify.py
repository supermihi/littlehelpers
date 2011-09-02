#!/usr/bin/python
# -*- coding: utf-8 -*-
# Makes flac files out of lossy files in the current directory
# by ripping the disc inside your CD-ROM drive and copying tags
# from the existing files.
# Assumes:
# - sorted filenames of the existing files are in the same order as
#   on the CD
# - no other files in current directory
# depends: abcde, flac, mutagen

import subprocess
import sys, os, os.path, glob
from mutagen import File

ripper_cmd = ["abcde"]
ripper_opts = ["-aread,encode,clean","-n","-N","-oflac","-x"]
if len(sys.argv) > 1 and sys.argv[1] == "1":
	ripper_opts.append("-d/dev/sr1")

numfiles = len(os.listdir(os.getcwd()))
# 1.: Rip the cd with abcde

subprocess.call(ripper_cmd + ripper_opts)

# 2.: Test if the number of files (and probably length / musicbrainz fingerprint?) coincide



# 3.: copy the tags and rename files

oldfiles = sorted(os.listdir(os.getcwd()))
for f in oldfiles:
	if not os.path.isfile(f):
		oldfiles.remove(f)
newfiles = sorted(glob.glob("abcde*/*.flac"))
if len(newfiles) != numfiles:
	print("Anzahl der Tracks stimmt nicht überein!")
	print(oldfiles)
	print("---")
	print(newfiles)
	sys.exit(1)
for i in range(len(oldfiles)):
	new_audio = File(newfiles[i])
	old_audio = File(oldfiles[i])
	for key in old_audio.keys():
		new_audio[key] = old_audio[key]
	new_audio.save()
	newname = oldfiles[i].rsplit(".",1)[0] + ".flac"
	os.rename(newfiles[i],newname)
	print("successfully tagged and renamed " + newname)

subprocess.call(["rm", "-rf"] + glob.glob("abcde*"))
ans = raw_input("Delete ogg files? [Y/n] ").strip()
if ans in "yYjJ" or ans == "":
	for f in oldfiles:
		os.remove(f)
