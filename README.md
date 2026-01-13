# TsMon
tsmon.p4 : main p4 program file, use blow commands to run this 
dmac.p4  : direct forwarding program, baseline
test_register.py : control plane program


# Run the Program
In three different terminals 

## 0. Environment Variable
```bash

source set_sde.bash           // 当无法build program的时候使用
bf_kdrv_mod_load $SDE_INSTALL // 当无法使用port-add的时候使用
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

配置端口
port-add 7/0 100g rs
port-add 8/0 100g rs
port-enb -/- 
```

---

# 解释区

Ingress 和 Egress实际上是共用一系列硬件设备，如12个stage

寄存器只能访问一次的强力解释: 每个stage有独立的寄存器阵列和ALU, 不能相互访问.

查看表分配情况路径:
/root/onl-bf-sde/build/p4-build/tofino/Program Name/Program Name/tofino/pipe/logs

