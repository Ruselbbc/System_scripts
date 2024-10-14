#! /usr/bin/env python
# -*- coding: utf-8 -*-

import re

""" The log file must have the nginx output structure as indicated below """

# log = '10.xx.xx.xx - - [04/Mar/2024:11:56:17 +0300 - 0.030] 200 "GET / HTTP/1.1" 11706 "-" "Mozilla/5.0 (Windows NT
# 6.1; WOW64; Trident/7.0; rv:11.0)" "-"[request_time=10.030, upstream_response_time=0.030, cache=-] (upstream
# 127.0.0.1:8888 // 200)" [bitrixtest.elko.ru] [HTTP/1.1]'

path = 'Z:/Sys admin/test.txt'
f = open(path, 'r')  # open file
str_f = f.read()

"""get an array of the first numbers, convert them into an entire string and return the result"""


def get_format_request(file_string):
    sublog = file_string.partition("request_time=")[2]
    seconds_array_in_log = re.findall(r'\w+', sublog)[0:2]
    seconds_in_log = float('.'.join(seconds_array_in_log))

    return seconds_in_log


#    print(seconds_in_log)

def get_format_response(file_string):
    sublog = file_string.partition("upstream_response_time=")[2]
    seconds_array_in_log = re.findall(r'\w+', sublog)[0:2]
    #    print(seconds_array_in_log)
    seconds_in_log = '.'.join(seconds_array_in_log)
    return seconds_in_log


"""  output the request and response time from all lines of the log file, bring it to the desired type and compare it 
with the border.
If the border is higher than the specified one, then output the line """
with open(path) as file_in:
    lines = []
    print('requests: ')
    for line in file_in:
        lines.append(line)
        if get_format_request(line) >= 60.000:
            print(line)
print('============================================')

# print(get_format_response(str_f))

with open(path) as file_in:
    lines = []
    print('responses: ')
    for line in file_in:
        lines.append(line)
        if get_format_response(line) >= '10.000' and get_format_response(line) != 'cache.upstream':
            print(line)

f.close()
