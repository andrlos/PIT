# PIT
Parallel Install Test for rpms

## Purpose
For testing parallel install ability of legacy RH builds.

## How to run
User needs to first export BUILD_OS_VERSION (number) and BUILD_OS_NAME (el or f) for the test to work.
Execution requires two arguments for two folders of rpms we want to install. The get installed in the order of the arguments. Running the test should then be just a simple execution of the shell script.
User can also influence where the produced logs will be stored by exporting TMPRESULTS variable.
