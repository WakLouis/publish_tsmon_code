# TsMon
tsmon.p4 : main p4 program file, use blow commands to run this 
dmac.p4  : direct forwarding program, baseline
test_register.py : control plane program


# Run the Program
In three different terminals 

## 0. Environment Variable
```bash

source set_sde.bash           
bf_kdrv_mod_load $SDE_INSTALL 
```
## 1. compile commands
``` bash
bash

cd ~/bf-sde-9.7.0/
./p4_build.sh --with-tofino ./LJY_P4/TsMon/tsmon.p4
```

## 2. start commands
```bash
bash

./run_switchd.sh -p tsmon
```

## 3. test commands
```bash
bash

./run_p4_tests.sh -p tsmon -t ./LJY_P4/TsMon/
```

# Commands in bfshell
```bash
ucli
pm

port-add 7/0 100g rs
port-add 8/0 100g rs
port-enb -/- 
```