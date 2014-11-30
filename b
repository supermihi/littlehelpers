#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
from os.path import join, expanduser, exists, expandvars, getmtime, isdir
import sys
import re
import subprocess
import configparser
import datetime

DATE_FORMAT = "%Y-%m-%d %H.%M"  # date format used in config files – don't change ;)
RSYNC_CMD = "rsync"
RSYNC_DEFAULT_ARGS = ["--exclude=lost+found",
                      "--delete",
                      "--delete-excluded",
                      "--ignore-errors",
                      "--verbose",
                      "--recursive",
                      "--links",
                      "--perms",
                      "--times",
                      "--group",
                      "--owner",
                      "--one-file-system",
                      "--hard-links",
                      "--partial",
                      "--progress"]
DEFAULT_INTERVAL = 12
WARNING_MESSAGE = ('Backup profile "{profile}" was last completed {last} ('
                   'configured interval is {interval} days)')


def yesNoQuestion(title, text):
    """Displays a yes-no question"""
    # ans = subprocess.call(['zenity', '--question', '--title', title, '--text', text])
    print(title)
    print(text)
    ans = input('(y/n)')
    return ans in 'yY'


def warning(title, text):
    """Displays a warning"""
    print(title)
    print(text)
    input()
    #subprocess.check_call(['zenity', '--warning', '--title', title, '--text', text])


class RsyncRunException(Exception):
    pass


class Profile:

    def __init__(self, confpath, name, section):
        self.name = name
        self.confpath = confpath
        self.device = section.get('device', None)
        self.target = section.get('target', '')
        self.mountpoint = None
        self.mount_sudo = section.getboolean('mount_sudo', False)
        self.umount_crypt = section.getboolean('umount_crypt', False)
        self.rsync_opts = RSYNC_DEFAULT_ARGS[:]
        if 'rsync_opts' in section:
            self.rsync_opts.extend(section['rsync_opts'].split())
        if 'paths' in section:
            self.paths = section['paths'].split(',')
        else:
            self.paths = []
        self.interval = datetime.timedelta(days=section.getint('interval', DEFAULT_INTERVAL))

        # read last and running state
        self.last = datetime.datetime.min
        if exists(self.lastPath):
            with open(self.lastPath, 'rt') as lastFile:
                self.last = datetime.datetime.strptime(lastFile.read().strip(), DATE_FORMAT)
        try:
            self.running = datetime.datetime.fromtimestamp(getmtime(self.runningPath))
        except FileNotFoundError:
            self.running = False

    @property
    def targetBase(self):
        return join(self.mountpoint, self.target) if self.mountpoint else self.target

    def mount(self):
        """Tries to mount (and, if necessary, decrypt) the device. Silently does nothing if there is
        no device specified.
        """
        if not self.device:
            return
        # check if already mounted
        command = ['udisksctl', 'info', '--block-device', self.device]
        output = subprocess.check_output(command).decode()
        ans = re.findall(r'^\s*MountPoints:[ ]*(\S+)$', output, flags=re.MULTILINE)
        if len(ans) == 0:
            command = ['udisksctl', 'mount', '--block-device', self.device]
            if self.mount_sudo:
                command[0:0] = 'sudo'
            output = subprocess.check_output(command).decode()
            self.mountpoint = re.findall(r'Mounted \S* at (\S*)\.$', output)[0]
        else:
            self.mountpoint = ans[0]

    @property
    def runningPath(self):
        return join(self.confpath, '.running_{}'.format(self.name))

    @property
    def lastPath(self):
        return join(self.confpath, '.last_backup_{}'.format(self.name))

    def isExpired(self):
        return datetime.datetime.now() - self.last > self.interval

    def probablyCrashed(self):
        return self.running and (datetime.datetime.now() - self.running).seconds >= 1800

    def touchRunning(self):
        with open(self.runningPath, 'wt') as f:
            pass

    def removeRunning(self):
        os.remove(self.runningPath)
    
    def finish(self):
        """Unmount device (if applicable) and store date."""
        now = datetime.datetime.now()
        last = now.strftime(DATE_FORMAT)
        with open(self.lastPath, 'wt') as lastout:
            lastout.write(last)
        if self.mountpoint:
            command = ['udisksctl', 'unmount', '--block-device', self.device]
            if self.mount_sudo:
                command[0:0] = ['sudo']
            subprocess.check_call(command)
            self.mountpoint = None

    def __str__(self):
        return self.name


class Path:

    def __init__(self, name, section):
        self.name = name
        self.source = None
        self.dest = ''
        self.inherit_excludes = section.get('inherit_excludes', None)
        if 'source' in section:
            self.source = expanduser(expandvars(section['source']))
        if 'dest' in section:
            self.dest = expanduser(expandvars(section['dest']))
        self.sudo = section.getboolean('sudo', False)
        self.versions = section.getint('versions', False)


class BackupConfiguration:

    def __init__(self, confpath):
        self.confpath = confpath
        self.profiles = {}
        self.paths = {}

    def readProfiles(self):
        parser = configparser.ConfigParser()
        parser.read(join(self.confpath, 'profiles'))
        for pName in parser.sections():
            profile = Profile(self.confpath, pName, parser[pName])
            self.profiles[pName] = profile
            
    def readPaths(self):
        parser = configparser.ConfigParser()
        parser.read(join(self.confpath, 'paths'))
        for path in parser.sections():
            self.paths[path] = Path(path, parser[path])

    def findProfile(self):
        """Tries to automagically determine the profile by existence of its device file."""
        # --- determine which profile to use ---
        for profile in self.profiles.values():
            if profile.device and exists(profile.device):
                return profile

    def check(self):
        """Checks for profiles that are 'over time', prints a warning message for each of such."""
        for profile in self.profiles.values():
            if profile.probablyCrashed():
                warning('Profile "{}" probably crashed'.format(profile),
                        'Profile "{}" running since {}. This is probably wrong?'
                        .format(profile, profile.running))
            elif profile.running:
                continue
            elif profile.isExpired():
                msg = WARNING_MESSAGE.format(profile=profile, last=profile.last,
                                             interval=profile.interval.days)
                if not profile.device or exists(profile.device):
                    if yesNoQuestion('Backup outdated', msg + '\nStart now?'):
                        self.doBackup(profile)
                else:
                    warning('Backup outdated', msg)

    def doBackup(self, profile):
        backupErrors = 0
        profile.touchRunning()
        try:
            profile.mount()
            for path in profile.paths:
                try:
                    self.backupPath(profile, self.paths[path])
                    print('Path {} successfully completed'.format(path))
                except RsyncRunException as rse:
                    backupErrors += 1
                    warning('Backup failed',
                            'Backup of {} failed; rsync terminated with the following message:\n'
                            .format(path, rse))
            profile.finish()
            if profile.device:
                warning('Backup finished', 'Please turn off the device "{}"'.format(profile.device))
            if backupErrors > 0:
                warning('{} errors occured during backup. Please check!'.format(backupErrors))
                return 1
        finally:
            profile.removeRunning()

    def excludes(self, path):
        """Returns a list of excludes (direct ones plus all inherited)."""
        if path.inherit_excludes:
            excludes = self.excludes(self.paths[path.inherit_excludes])
        else:
            excludes = []
        exclFile = join(self.confpath, 'excludes', path.name)
        if exists(exclFile):
            excludes.append(exclFile)
        return excludes

    def backupPath(self, profile, path):
        """Runs the rsync command for a single path. Assumes that everythings's
        mounted & decrypted."""
        source = path.source
        dest = join(profile.targetBase, path.dest)
        # ensure the target exists (if it's not an SSH path)
        if not exists(dest) and ':' not in profile.targetBase:
            try:
                os.makedirs(dest)
            except OSError as e:
                raise RsyncRunException('Error creating target directory {}'.format(e))
        excludes = self.excludes(path)
        rsyncOpts = profile.rsync_opts[:]
        for excludefile in excludes:
            rsyncOpts.append('--exclude-from=' + excludefile)
        if path.versions:
            # tricky part: keep several hardlinked versions
            if path.versions < 1:
                raise ValueError("<1 versions requested, check your config file")
            existingVersions = []
            for existingSubdir in os.listdir(dest):
                if not isdir(join(dest, existingSubdir)):
                    continue
                try:
                    date = datetime.datetime.strptime(existingSubdir, DATE_FORMAT)
                    existingVersions.append(date)
                except ValueError:
                    print('Subdirectory {} of {} is not a backup'.format(existingSubdir, dest))
                    continue
            existingVersions.sort() #earliest first
            for oldversion in existingVersions[:-path.versions + 1]:
                # delete old backups
                command = ['rm', '-rf', join(dest, oldversion.strftime(DATE_FORMAT))]
                if path.sudo:
                    command.insert(0, 'sudo')
                print('Executing command: {}'.format(' '.join(command)))
                subprocess.check_call(command)
            for linkversion in existingVersions[-path.versions + 1:]:
                rsyncOpts.append('--link-dest=' + join(dest, linkversion.strftime(DATE_FORMAT)))
            fulldest = join(dest, datetime.datetime.now().strftime(DATE_FORMAT))
        else:
            fulldest = dest
        command = [RSYNC_CMD] + rsyncOpts +  [source + '/', fulldest + '/']
        if path.sudo:
            command.insert(0, 'sudo')
        print("Executing command: \n" + " ".join(command))
        try:
            rsyncProc = subprocess.Popen(command, stderr=subprocess.PIPE)
            stdout, stderr = rsyncProc.communicate()
        except KeyboardInterrupt:
            raise RsyncRunException("Rsync interrupted by Keyboard")
        except OSError as e:
            raise RsyncRunException("Problem calling rsync: {0}".format(str(e)))
        if rsyncProc.returncode != 0:
            raise RsyncRunException("Rsync exited with non-zero return code:\n\n{0}".format(stderr.decode()))


if __name__ == '__main__':
    try:
        import xdg.BaseDirectory
        confPath = join(xdg.BaseDirectory.xdg_config_home, 'b')
    except ImportError:
        confPath = expanduser('~/.config/b')
    config = BackupConfiguration(confPath)
    config.readProfiles()
    config.readPaths()
    if len(sys.argv) > 1 and sys.argv[1] == "check":
        config.check()
    else:
        if len(sys.argv) > 1:
            profile = config.profiles[sys.argv[1]]
        else:
            profile = config.findProfile()
        if profile:
            returncode = config.doBackup(profile)
            sys.exit(returncode)
