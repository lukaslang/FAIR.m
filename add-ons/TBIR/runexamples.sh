#!/bin/bash
LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libstdc++.so.6 \
LD_LIBRARY_PATH=/home/ll542/store/git/astra/lib \
nohup nice matlab-r2017b -nodisplay -nojvm -nosplash -nodesktop -r "run('../../FAIRstartup.m'); run('TBIRstartup.m'); try; run('ex_0.m'); run('ex_1a.m'); run('ex_1b.m'); run('ex_2.m'); run('ex_3.m'); run('ex_4.m'); run('ex_5.m'); run('ex_6.m'); run('ex_7.m'); run('ex_8.m'); catch ME; disp(ME); disp(getReport(ME, 'extended', 'hyperlinks', 'off')); exit(1); end; exit(0);" > runexamples.log 2>&1
