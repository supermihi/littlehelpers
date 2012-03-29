#!/usr/bin/python3
# coding=UTF8
# "decodes" text that was typed on a NEO layout keyboard while
# the user though it was QWERTZ.

qwertz = 'qwertzuiopü+asdfghjklöä#<yxcvbnm,.- '
neo = 'xvlcwkhgfqß´uiaeosnrtdy[]üöäpzbm,.j '
qwertz_to_neo = dict(zip(qwertz,neo))
neo_to_qwertz = dict(zip(neo,qwertz))
def n_to_q(c):
    try:
        return neo_to_qwertz[c]
    except KeyError:
        return c
    
import sys
with open(sys.argv[1],'rt') as file:
    text = file.read()
print("".join(n_to_q(i.lower()) for i in text))
