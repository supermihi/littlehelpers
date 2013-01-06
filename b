#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os, os.path
import sys
import subprocess
import configparser
import datetime
import gettext
import time
import copy
import readline

_ = gettext.gettext

# -------- "almost constant" program parameters
confdir = os.path.expanduser("~/.b") # where we look for configuration files
DATE_FORMAT = "%Y-%m-%d %H.%M" # date format used in config files – don't change ;)
RSYNC_CMD = "rsync"
RSYNC_DEFAULT_ARGS =    ["--exclude=lost+found", "--delete", "--delete-excluded", "--ignore-errors", "-v", "-a", "-x", "-H", "-P"]
PROFILE_CONF_PATH = os.path.join(confdir, "profiles") # main config file where profiles are defined
PATH_CONF_PATH = os.path.join(confdir, "paths") # config file for the paths
DEFAULT_INTERVAL = 12

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
class Options:
    def __init__(self):
        self.interactivity="delay"
        self.interactivity_delay=2
        self.motzmessage=_(
            "******************************* WARNUNG ********************************\n" +  
            "************************************************************************\n" +
            "** Echt, du Spast .... könntest mal wieder was für deine\n" +
            '** Datensicherheit tun! Das Backup-Profil "{profile}" wurde seit\n' +
            "** sage und schreibe !!!{last}!!! Tagen nicht mehr gesichert;\n" + 
            "** dabei ist das geforderte Intervall für dieses Profil auf\n" +
            "** !!!{interval}!!! Tage gesetzt.\n" + 
            "** ZOMGGG!!!!111111einseinself Möge das Höllenfeuer sofort\n" + 
            "** deine Festplatten fressen.\n" + 
            "************************************************************************\n" + 
            "************************************************************************")
        self.profile_default = {
            "device":None,
            "crypttab_name":None,
            "mountpoint":None,
            "paths":[],
            "last":datetime.datetime.min,
            "interval":datetime.timedelta(days=DEFAULT_INTERVAL),
            "target":"",
            "mount_sudo":None,
            "umount_crypt":False,
            "rsync_opts":""
        }
        
        self.profiles = {}
        
        self.path_default = {
            "source":None,
            "dest":"",
            "inherit_excludes":None,
            "sudo":False,
            "versions":None
        }
        
        self.paths = {}
    def read_profiles(self):
        parser = configparser.ConfigParser()
        parser.read(PROFILE_CONF_PATH)
        for profile in parser.sections():
            self.profiles[profile] = copy.copy(self.profile_default)
            for option in parser.options(profile):
                if not option in self.profile_default:
                    # option in config file that is not understood by this program
                    print(_("WARNING: The option '{0}' in {1} is not a valid profile option.").format(option, PROFILE_CONF_PATH))
                
                parser_option = parser.get(profile,option)
                if option in ["device", "crypttab_name", "mountpoint", "target", "mount_sudo", "umount_crypt", "rsync_opts"]: # string options -- just copy
                    self.profiles[profile][option] = parser_option
                elif option in ["paths"]: # list options, separated by comma
                    self.profiles[profile][option] = parser_option.split(',')
                elif option in ["interval"]: # time interval options
                    self.profiles[profile][option] = datetime.timedelta(days = int(parser_option))
            if os.path.exists(os.path.join(confdir, ".last_backup_" + profile)):
                with open(os.path.join(confdir, ".last_backup_" + profile)) as lastfile:
                    string = lastfile.read().strip()
                    self.profiles[profile]["last"] = datetime.datetime.strptime(string, DATE_FORMAT)
            
    def read_paths(self):
        parser = configparser.ConfigParser()
        parser.read(PATH_CONF_PATH)
        for path in parser.sections():
            self.paths[path] = copy.copy(self.path_default)
            for option in parser.options(path):
                if not option in self.path_default:
                    print(_("WARNING: The option '{0}' in {1} is not a valid path option.").format(option, PATH_CONF_PATH))

                if option in ["source", "dest"]:
                    self.paths[path][option] = os.path.expanduser(os.path.expandvars(parser.get(path,option)))
                elif option == "inherit_excludes": # string options
                    self.paths[path][option] = parser.get(path,option)
                elif option in ["sudo"]:
                    self.paths[path][option] = parser.getboolean(path,option)
                elif option in ["versions"]:
                    self.paths[path][option] = parser.getint(path,option)
# ~~~~~~ END class Options ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

class RsyncRunException(Exception):
    def __init__(self, what):
        self.what = what
    
    def __str__(self):
        return self.what

# --- global stuff, should be moved in some class some day
options = Options()
options.read_profiles()
options.read_paths()
profiles = options.profiles.keys()

def interact():
    """According to the interactivity option, wait for confirmation, do a time delay or just display the message."""
    mode = options.interactivity
    delay = options.interactivity_delay
    if mode=="confirm":
        input(_("Press 'Enter' to continue..."))
    elif mode=="delay":
        print(_("Waiting {0} seconds to continue...").format(str(delay)), end='')
        try:
            for secs in reversed(range(1,delay)):
                sys.stdout.flush()
                time.sleep(1)
                print(str(secs) + "...",end='')
                sys.stdout.flush()
        except KeyboardInterrupt:
            print(_("Aborting delay due to keyboard interrupt"))
        print()
    else: # just go on
        pass
# ~~~~~~ END interact() ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def check(oneLine = False):
    """Checks for profiles that are 'over time', prints a warning message for each of such."""
    msgs = []
    for pname,profile in options.profiles.items():
        if profile["device"] and os.path.exists(profile["device"]):
            if not oneLine:
                print("CAUTION: device {} is available for backup.".format(pname))
                ans = input("Do you want to start a backup? [Y/n] ")
                if ans in ( "y", "Y", ""):
                    do_backup(pname)
            else:
                msgs.append("Backup-dev {} available".format(pname))
                
        last = profile["last"]
        maxinterval = profile["interval"]
        now = datetime.datetime.now()
        if (now - last) > maxinterval:
            if oneLine:
                msgs.append("BACKUP {} OUTDATED: {} DAYS".format(pname, (now-last).days))
            else:
                print(options.motzmessage.format(profile = pname, last = (now - last).days, interval = maxinterval.days))
                sys.stdout.flush()
                if not profile["device"]:
                    ans = input("could start now -- ok? [Y/n] ")
                    if ans in ("y", "Y", ""):
                        do_backup(pname)
    if oneLine:
        print("; ".join(msgs))
                
            
# ~~~~~~ END check() ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def mount(mountpoint, sudo = False):
    """Mounts the given mountpoint, if it isn't mounted already."""
    
    # check if already mounted
    with open("/etc/mtab") as mtab:
        for line in mtab:
            mp = line.split()[1].replace("\\040", " ") # spaces are encoded in mtab to preserve the formatting
            if mp == mountpoint:
                print("Filesystem already mounted.")
                return
    # need to mount
    if sudo:
        print('executing: "sudo mount {}"'.format(mountpoint))
        subprocess.check_call(["sudo", "mount", mountpoint])
    else:
        print('executing: "mount {}"'.format(mountpoint))
        subprocess.check_call(["mount", mountpoint])
# ~~~~~~ END mount(mountpoint) ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def get_excludes(path):
    """Returns a list of excludes for the given path, that is, the direct ones plus all inherited."""
    if options.paths[path]["inherit_excludes"]:
        excludes = get_excludes(options.paths[path]["inherit_excludes"])
    else:
        excludes = []
    excl_file = os.path.join(confdir, "excludes", path)
    if os.path.exists(excl_file):
        excludes.append(excl_file)
    return excludes


def do_path(profile, path, target_base):
    """Runs the rsync command for a single path. Assumes that everythings's mounted & decrypted."""
    pathopts = options.paths[path]
    source = pathopts["source"]
    dest = os.path.join(target_base,pathopts["dest"])
    if not os.path.exists(dest) and not ':' in target_base: # make sure the target exists (if it's not an SSH path)
        try:
            os.makedirs(dest)
        except OSError as e:
            raise RsyncRunException(_("Target directory does not exist and cannot create it: {0}").format(str(e)))
    rsync_opts = RSYNC_DEFAULT_ARGS
    if options.profiles[profile]["rsync_opts"] != "":
        rsync_opts.append(options.profiles[profile]["rsync_opts"])
    excludes = get_excludes(path)
    for excludefile in excludes:
        rsync_opts.append("--exclude-from=" + excludefile)
    if pathopts["versions"]:
        # tricky part: keep several hardlinked versions
        versions = pathopts["versions"]
        if versions < 1:
            print(_("nasty bastard"))
            raise ValueError(_("<1 versions requested, check your config file"))
        existing_versions = []
        for existing_subdir in os.listdir(dest):
            if not os.path.isdir(os.path.join(dest,existing_subdir)):
                continue
            try:
                date = datetime.datetime.strptime(existing_subdir, DATE_FORMAT)
                existing_versions.append(date)
            except ValueError:
                print(_("There is a subdir in the backup path that's not a backup: {0}").format(existing_subdir))
                continue # dirty subdir
        existing_versions.sort() #earliest first
        for oldversion in existing_versions[:-versions+1]: #delete old backups
            
            rm_cmd = "rm -rf '{0}'".format(os.path.join(dest,oldversion.strftime(DATE_FORMAT)).replace("'","\'"))
            if pathopts["sudo"]:
                rm_cmd = "sudo " + rm_cmd
            print(_("Executing command {0}").format(rm_cmd))
            os.system(rm_cmd)
        for linkversion in existing_versions[-versions+1:]:
            rsync_opts.append("--link-dest="+os.path.join(dest,linkversion.strftime(DATE_FORMAT)))
        fulldest = os.path.join(dest, datetime.datetime.now().strftime(DATE_FORMAT))
    else:
        fulldest = dest
    command = [RSYNC_CMD] + rsync_opts +  [source + "/", fulldest + "/"]
    if pathopts["sudo"]:
        command[:0] = ["sudo"]
    print(_("I will now execute this command: \n") + " ".join(command))
    interact()
    try:
        rsync_proc = subprocess.Popen(command, stderr=subprocess.PIPE)
        stdout, stderr = rsync_proc.communicate()
    except KeyboardInterrupt:
        raise RsyncRunException(_("Rsync interrupted by Keyboard"))
    except OSError as e:
        raise RsyncRunException(_("Problem calling rsync: {0}").format(str(e)))
    if rsync_proc.returncode != 0:
        raise RsyncRunException(_("Rsync exited with non-zero return code:\n\n{0}").format(stderr.decode('utf8')))
# ~~~~~~ END do_path(path, target_base) ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

def find_profile():
    """Tries to automagically determine the profile by existence of its device file."""
    profile = ""
    # --- determine which profile to use ---
    for p in profiles:
        if options.profiles[p]["device"] and os.path.exists(options.profiles[p]["device"]):
            return p
    if profile=="":
        print(_("Did not find any backup device. You have to choose a profile manually."))
        return None

def do_backup(profile):
    profopts = options.profiles[profile]
    need_decrypt = profopts["crypttab_name"]
    need_mount = profopts["mountpoint"]
    mount_sudo = profopts["mount_sudo"]
    umount_crypt = profopts["umount_crypt"]
    backup_errors = 0
    if need_decrypt: 
        # we need to decrypt first
        try:
            print('executing: "sudo cryptdisks_start {}"'.format(profopts["crypttab_name"]))
            subprocess.check_call(["sudo", "cryptdisks_start", profopts["crypttab_name"]])
        except subprocess.CalledProcessError:
            print(_("Unable to decrypt device."))
            return 17
    if need_mount:
        mountpoint = profopts["mountpoint"]
        target_base = os.path.join(mountpoint,profopts["target"])
        try:
            mount(mountpoint, mount_sudo)
        except subprocess.CalledProcessError:
            print(_("Unable to mount device."))
            return 19
    else:
        target_base = profopts["target"]
    
    for path in profopts["paths"]:
        try:
            do_path(profile, path, target_base)
            print("path {} finished successful".format(path))
        except RsyncRunException as rse:
            backup_errors = backup_errors + 1
            print(_("Error backing up {0}, rsync faild with {1}").format(path,rse.what))
            input()
  
    if need_mount:
        command = ["umount.crypt" if umount_crypt else "umount"]
        if mount_sudo:
            command[0:0] = ["sudo"]
        try:
            subprocess.check_call(command + [mountpoint])
        except:
            print(_("WARNING: Failed to unmount device."))
            if not need_decrypt:
                return 27
    if need_decrypt:
        try:
            subprocess.check_call(["sudo", "cryptdisks_stop", profopts["crypttab_name"]])
        except:
            print(_("WARNING: Faild to close encrypted device. THIS IS A SECURITY RISK, PLEASE TAKE CARE OF THAT!!!"))
            interact()
            return 29
    # now we are done -- store last success time
    now = datetime.datetime.now()
    last =  now.strftime(DATE_FORMAT)
    with open(os.path.join(confdir, ".last_backup_" + profile), 'w') as lastout:
        lastout.write(last)
    if profopts["device"]:
        print("Now, please remember to turn off the device".format(profile))
    if backup_errors > 0:
        print(_("There were {0} errors during the backup. Please check this!").format(backup_errors))
        return 1
# ~~~~~~ END do_backup(profile) ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1][:5] == "check":
        if sys.argv[1] == "check":
            check()
        elif sys.argv[1] == "check1":
            check(True)
    else:
        if len(sys.argv) > 1:
            profile = sys.argv[1]
        else:
            profile = find_profile()
        if profile:
            returncode = do_backup(profile)
            sys.exit(returncode)
