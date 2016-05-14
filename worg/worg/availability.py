import os.path
import subprocess


class BackupNotAvailableException(RuntimeError):
    pass


class AvailabilityChecker:

    def isAvailable(self):
        raise NotImplementedError()

    def message(self):
        raise NotImplementedError()

    def assertAvailable(self):
        if not self.isAvailable():
            raise BackupNotAvailableException(self.message())


class DeviceAvailabilityChecker(AvailabilityChecker):

    def __init__(self, path):
        self.path = path

    def isAvailable(self):
        return self.path and os.path.exists(self.path)

    def message(self):
        return "Device {} not available".format(self.path)


class PingAvailabilityChecker(AvailabilityChecker):

    def __init__(self, url):
        self.url = url

    def isAvailable(self):
        if self.url is None:
            return False
        return subprocess.call(['ping', '-c1', '-q', '-W1', self.url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def message(self):
        return "URL {} not available".format(self.path)


class AlwaysAvailableAvailabilityChecker(AvailabilityChecker):

    def isAvailable(self):
        return True

    def message(self):
        return "Should not see this!"


def parse(config):
    if config['type'] == 'device':
        return DeviceAvailabilityChecker(config['path'])
    if config['type'] == 'url':
        return PingAvailabilityChecker(config['url'])
    raise RuntimeError()

if __name__ == '__main__':
    parse({'type': 'device', 'path': 'omg'})