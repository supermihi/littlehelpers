import os.path
import subprocess


class DeviceAvailabilityChecker:

    def __init__(self, path):
        self.path = path

    def isAvailable(self):
        return self.path and os.path.exists(self.path)

    def message(self):
        return "Device {} not available".format(self.path)


class PingAvailabilityChecker:

    def __init__(self, url):
        self.url = url

    def isAvailable(self):
        if self.url is None:
            return False
        return subprocess.call(['ping', '-c1', '-q', '-W1', self.url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def parse(config):
    if config['type'] == 'device':
        return DeviceAvailabilityChecker(config['path'])
    if config['type'] == 'url':
        return PingAvailabilityChecker(config['url'])
    raise RuntimeError()

if __name__ == '__main__':
    parse({'type': 'device', 'path': 'omg'})