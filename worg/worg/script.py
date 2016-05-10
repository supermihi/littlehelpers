from os.path import join
import datetime
import json
import sys


def run():

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
        interval = datetime.timedelta(days=section['interval'])
        command = section['command']
        name = section['name']
        profiles[name] = worg.Profile(name, interval, command, avail)

    if len(sys.argv) == 1:
        for profile in profiles.values():
            if profile.isDue():
                print('{} is due!'.format(profile))
                print('last backup: {}'.format(profile.lastCompleted()))
    else:
        name = sys.argv[1]
        if name in profiles:
            profiles[name].run()


