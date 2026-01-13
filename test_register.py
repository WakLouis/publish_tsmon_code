################################################################################
# BAREFOOT NETWORKS CONFIDENTIAL & PROPRIETARY
#
# Copyright (c) 2019-present Barefoot Networks, Inc.
#
# All Rights Reserved.
#
# NOTICE: All information contained herein is, and remains the property of
# Barefoot Networks, Inc. and its suppliers, if any. The intellectual and
# technical concepts contained herein are proprietary to Barefoot Networks, Inc.
# and its suppliers and may be covered by U.S. and Foreign Patents, patents in
# process, and are protected by trade secret or copyright law.  Dissemination of
# this information or reproduction of this material is strictly forbidden unless
# prior written permission is obtained from Barefoot Networks, Inc.
#
# No warranty, explicit or implicit is provided, unless granted under a written
# agreement with Barefoot Networks, Inc.
#
################################################################################

import logging
import time

from ptf import config
import ptf.testutils as testutils
from bfruntime_client_base_tests import BfRuntimeTest
import bfrt_grpc.bfruntime_pb2 as bfruntime_pb2
import bfrt_grpc.client as gc
import random

logger = logging.getLogger('Test')
if not len(logger.handlers):
    logger.addHandler(logging.StreamHandler())

num_pipes = int(testutils.test_param_get('num_pipes'))
pipes = list(range(num_pipes))

swports = []
for device, port, ifname in config["interfaces"]:
    
    pipe = port >> 7
    if pipe in pipes:
        swports.append(port)
swports.sort()

class ReadRegister(BfRuntimeTest):
    def setUp(self):
        client_id = 0
        p4_name = 'tsmon'
        BfRuntimeTest.setUp(self, client_id, p4_name)

    def runTest(self):
        bfrt_info = self.interface.bfrt_info_get("tsmon")
        mean_table = bfrt_info.table_get("SwitchIngress.tsSketch.mean_processor")
        sq_mean_table = bfrt_info.table_get("SwitchIngress.tsSketch.sq_mean_processor")
        target = gc.Target(device_id=0, pipe_id=0xffff)
        register_idx = 0

        # registers = ['TsQueue0', 'TsQueue1', 'TsQueue2', 'TsQueue3', 'TsQueue4', 'TsQueue5', 'TsQueue6', 'TsQueue7']
        registers = ['eg_temp_1', 'eg_temp_2', 'eg_temp_3', 'eg_temp_4', 'eg_temp_5']
        mean_table.entry_del(target)
        sq_mean_table.entry_del(target)
        mean_table.entry_add(
                target,
                [mean_table.make_key([gc.KeyTuple('$LPF_INDEX', 0)])],
                [mean_table.make_data(
                    [gc.DataTuple('$LPF_SPEC_TYPE', str_val='SAMPLE'),
                     gc.DataTuple('$LPF_SPEC_GAIN_TIME_CONSTANT_NS', float_val=5000000.0),
                     gc.DataTuple('$LPF_SPEC_DECAY_TIME_CONSTANT_NS', float_val=2500000.0),
                     gc.DataTuple('$LPF_SPEC_OUT_SCALE_DOWN_FACTOR', 0)])]
            )
        sq_mean_table.entry_add(
                target,
                [sq_mean_table.make_key([gc.KeyTuple('$LPF_INDEX', 0)])],
                [sq_mean_table.make_data(
                    [gc.DataTuple('$LPF_SPEC_TYPE', str_val='SAMPLE'),
                     gc.DataTuple('$LPF_SPEC_GAIN_TIME_CONSTANT_NS', float_val=5000000.0),
                     gc.DataTuple('$LPF_SPEC_DECAY_TIME_CONSTANT_NS', float_val=2500000.0),
                     gc.DataTuple('$LPF_SPEC_OUT_SCALE_DOWN_FACTOR', 0)])]
            )

        while(1):
            time.sleep(0.025)
            values = []

            for register in registers:
                
                self.register_bool_table = bfrt_info.table_get(register)
                resp = self.register_bool_table.entry_get(target, [self.register_bool_table.make_key([gc.KeyTuple('$REGISTER_INDEX', register_idx)])], {"from_hw": True})

                resp_dict = next(resp)[0].to_dict()

                value = 0
                for key, val in resp_dict.items():
                    # print(val)
                    if '.f1' in key:
                        value = val[1]
                        break

                values.append(value)

            # print(values)

            print('窗口总和:', values[0], '窗口峰值:', values[1], '平均速率', values[2], '方差', values[3], '检测结果', values[4], end=' ')

            if values[4] == 0:
                print('正常', end=' ')

            if values[4] & 1 == 1:
                print('一级超速,', end=' ')
            
            if values[4] & 2 == 2:
                print('二级超速,', end=' ')

            if values[4] & 4 == 4:
                print('异常种类A,', end=' ')

            if values[4] & 8 == 8:
                print('异常种类B,', end=' ')



            print('\n')

            
            

