#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#Filename: transsync.py
# Maintains a copy of a music collection, in which FLAC files are recoded to OGG Vorbis for space reasons.
# Other files are hard linked, so no additional space is wasted for them.

import os, subprocess, os.path
from threading import Thread
import queue
import sys, time, shutil, signal

import taglib

# ---- configuration -----------
sourcepath="/ftp/musik"
targetpath="/ftp/musiksmall"
oggopts=["-q5","-Q"] # quality 5 and quiet mode
threads = 4
hardlinks = True # use hardlinks instead of copying non-FLAC files
deleteold = True # delete existing files in target directory if they have older mtime than source
# ------------------------------

encodingJobs = queue.Queue() # contains tuples of source/target filenames to be encoded
copyingJobs = queue.Queue() # contains tuples of source/target filenames to be copied
t0 = time.time()
# initialize some stat vars
totalflacfiles = todoflacfiles  = filesencoded = todocopy = filescopied = flacsize = oggsize = 0
term = False
errorFiles = []
# --------------------------------------------------------------------------------------------
def encoder(name):
    """Worker function for an encoder thread."""
    
    global filesencoded, oggsize, flacsize, encodingJobs, term, errorFiles
    while not term:
        try:
            source, target = encodingJobs.get(timeout=0.1)
        except queue.Empty:
            return
        retcode = subprocess.call(["oggenc"] + oggopts + ["-o" + target, source])
        if not retcode == 0:
            if term:
                try:
                    os.remove(target)
                    print("Cleaning unfinished file {0}".format(target))
                except:
                    pass
                finally:
                    print("\nThread {0} returned.".format(name))
                    return
            else:
                errorFiles.append(source)
        else:
            filesencoded = filesencoded + 1
            print("\nThread {0} Successfully encoded {1}.".format(name,os.path.basename(target)))
            oggsize = oggsize + os.path.getsize(target)
            flacsize = flacsize + os.path.getsize(source)
        encodingJobs.task_done()
# ----------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------
def copier():
    """Worker function for a copy thread."""
    global filescopied
    while not copyingJobs.empty():
        source,target = copyingJobs.get()
        if os.path.exists(target):
            os.remove(target)
        if hardlinks:
            try:
                os.link(source,target)
            except OSError as e:
                print("Error copying file {1} to {2}: {0}".format(e,source,target))
        else:
            shutil.copy(source,target)
        filescopied = filescopied + 1
    print("\nCopier finished.")

# ----------------------------------------------------------------------------------------------

os.chdir(sourcepath)
bla = 0

# create target directory tree
for dirpath, dirnames, files in os.walk(sourcepath):
    for subdir in dirnames:
        relsubdir = os.path.relpath(os.path.join(dirpath,subdir))
        targetsubdir = os.path.join(targetpath, relsubdir)
        if not os.path.exists(targetsubdir):
            sys.stdout.write("\r" + " "*bla)
            ostring = "\rCreating directory {0}...".format(targetsubdir)
            bla = len(ostring)
            print(ostring,end='')
            os.mkdir(targetsubdir)
            #time.sleep(0.1)
            sys.stdout.flush()
                
sys.stdout.write("\r" + " "*bla)    
print("\rDone creating directories.")

# delete files without corresponding sources and empty folders
for dirpath, dirnames, files in os.walk(targetpath, topdown=False):
    for file in files:
        if os.path.exists(os.path.join(sourcepath,os.path.relpath(dirpath,targetpath),file)):
            continue
        if os.path.exists(os.path.join(sourcepath,os.path.relpath(dirpath,targetpath),file.rsplit(".",1)[0]+".flac")):
            continue
        print("deleting {0}".format(os.path.join(dirpath,file)))
        os.remove(os.path.join(dirpath,file))
    if len(files) == 0 and len(dirnames) == 0:
        print("removing directory {}".format(dirpath))
        os.rmdir(dirpath)

        

# add encoding and copying jobs
for dirpath, dirnames, files in os.walk(sourcepath):
    for file in files:
        try:
            sourcefile = os.path.join(dirpath,file)
            fileBase = file.rsplit(".",1)[0]
            fileExt = file.lower().rsplit(".",1)[1]
            if fileExt == "flac":
                totalflacfiles = totalflacfiles+1
                targetfile = os.path.join(targetpath,os.path.relpath(dirpath),fileBase + ".ogg")
                if (not os.path.exists(targetfile)):
                    encodingJobs.put((sourcefile,targetfile))
                    todoflacfiles = todoflacfiles + 1
                elif deleteold and os.stat(sourcefile)[8] > os.stat(targetfile)[8]: #stat[8] is mtime
                    encodingJobs.put((sourcefile,targetfile))
                    todoflacfiles = todoflacfiles + 1
            else:
                targetfile = os.path.join(targetpath,os.path.relpath(dirpath),file)
                if not os.path.exists(targetfile) or os.path.getsize(targetfile) != os.path.getsize(sourcefile) or os.path.getmtime(sourcefile) > os.path.getmtime(targetfile):
                    todocopy = todocopy+1
                    copyingJobs.put((sourcefile,targetfile))
        except IndexError:
            pass # splitting etc. fails - probably no audio file

# create and start threads
for i in range(threads):
    t = Thread(target=encoder,kwargs={"name":i})
    t.start()

c = Thread(target=copier)
c.start()

# main loop: fancy output
try:
    while not (encodingJobs.empty() and copyingJobs.empty()):
        sys.stdout.write("\r" + " "*bla)
        if flacsize > 0:
            ratio = oggsize / flacsize
        else:
            ratio= 0
        output = "{0} of {1} files encoded. {2} of {3} files copied. Shrunk from {4:.1f}MB flac size to {5:.1f}MB ogg size (ratio: {6:.3f}). {7:.2f} seconds elapsed.".format(filesencoded,
            todoflacfiles, filescopied, todocopy,
            flacsize/(1024*1024),
            oggsize/(1024*1024),
            ratio, time.time() - t0)
        bla = len(output)
        print("\r" + output,end="")
        sys.stdout.flush()
        time.sleep(0.2)
except KeyboardInterrupt:
    if len(errorFiles) > 0:
        print("")
        print("The following files failed to transcode:")
        for err in errorFiles:
            print(err)
    print("Waiting for threads to finish...")
    term = True
