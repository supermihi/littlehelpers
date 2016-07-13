from os.path import join
import datetime
import json
import sys


def run():
    import worg.availability

    profiles = createProfiles()
    exitcode = 0
    if len(sys.argv) == 1:
        availDueProfile = check(profiles)
        if availDueProfile is None:
            return
        else:
            userAns = input('Start now? [Yn]')
            if userAns in ['', 'Y', 'y']:
                availDueProfile.run()
    else:
        name = sys.argv[1]
        if name in profiles:
            try:
                profiles[name].run()
            except worg.availability.BackupNotAvailableException as e:
                print(e)
                exitcode = 1
        else:
            print('unknown backup profile {}'.format(name))
            exitcode = 1

    input('\npress any key to end worg ...')
    sys.exit(exitcode)


def createProfiles():
    import worg
    profilesPath = join(worg.confDirectory(), 'profiles')
    with open(profilesPath) as f:
        config = json.load(f)
    profiles = {}
    import worg.availability
    for section in config:
        avail = None
        if 'availchecker' in section:
            avail = worg.availability.parse(section['availchecker'])
        else:
            avail = worg.availability.AlwaysAvailableAvailabilityChecker()
        interval = datetime.timedelta(days=section['interval'])
        command = section['command']
        name = section['name']
        profiles[name] = worg.Profile(name, interval, command, avail)
    return profiles


def check(profiles):
    for profile in profiles.values():
        if profile.isDue():
            input('Backup "{}" is due! (Last completion time is {})'.format(profile, profile.lastCompleted()))
            if profile.canRun():
                return profile
