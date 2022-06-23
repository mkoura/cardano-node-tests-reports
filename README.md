Testing reports for cardano-node-tests
======================================

Publishing testing results
--------------------------

1. install the `allure` command line tool - https://docs.qameta.io/allure/#_installing_a_commandline
1. run tests in the cardano-node-tests repository (`make tests`)
1. publish the results to https://mkoura.github.io/cardano-node-tests-reports/
```
$ ./publi.sh path/to/cardano-node-tests/repository
```
