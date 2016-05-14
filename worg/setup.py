from setuptools import setup

setup(
    name='worg',
    version='',
    packages=['worg'],
    url='',
    license='',
    author='Michael Helmling',
    author_email='michaelhelmling@posteo.de',
    description='simple backup reminder script',
    install_requires=['python-dateutil', 'pyxdg'],
    entry_points={'console_scripts': ['worg = worg.script:run']},
)
