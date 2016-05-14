import datetime
import os
import os.path
from os.path import expanduser, isfile, join
import subprocess
import dateutil.parser


def confDirectory():
    try:
        import xdg.BaseDirectory
        return join(xdg.BaseDirectory.xdg_config_home, 'worg')
    except ImportError:
        return expanduser('~/.config/worg')


class Profile:

    def __init__(self, name, interval: datetime.timedelta, command: str, availChecker=None):
        self.name = name
        self.interval = interval
        self.command = command
        self.availChecker = availChecker

    @property
    def pidfile(self):
        return os.path.join('/tmp', 'worg_{}.pid'.format(self.name))

    def createPidfile(self):
        pid = str(os.getpid())
        open(self.pidfile, 'w').write(pid)

    def removePidfile(self):
        if isfile(self.pidfile):
            os.remove(self.pidfile)

    def runningPid(self):
        if isfile(self.pidfile):
            pid = open(self.pidfile, 'r').read()
            # todo check if process is running
            return pid

    @property
    def lastCompletedFile(self):
        return join(confDirectory(), 'last_complete_{}'.format(self.name))

    def lastCompleted(self):
        if isfile(self.lastCompletedFile):
            file = open(self.lastCompletedFile, 'rt').read()
            return dateutil.parser.parse(file.strip())
        return datetime.datetime.min

    def storeLastCompleted(self):
        now = datetime.datetime.now()
        last = now.isoformat()
        with open(self.lastCompletedFile, 'wt') as lastout:
            lastout.write(last)

    def isDue(self):
        now = datetime.datetime.now()
        last = self.lastCompleted()
        return now - last > self.interval

    def canRun(self):
        return self.availChecker is not None and self.availChecker.isAvailable()

    def run(self):
        pid = self.runningPid()
        if pid is not None:
            raise RuntimeError('Profile {} already running with PID {}'.format(self.name, pid))
        if not self.availChecker.isAvailable():
            raise RuntimeError(self.availChecker.message())
        self.createPidfile()
        try:
            print('Running backup profile "{}" ...'.format(self))
            subprocess.run(self.command, shell=True, check=True)
            print('Backup finished. Please unplug device!')
            self.storeLastCompleted()
        except subprocess.CalledProcessError as e:
            print('error: {}'.format(e))
        finally:
            self.removePidfile()

    def __str__(self):
        return self.name

if __name__ == '__main__':
    from worg import script
    script.run()






