#include <core.p4>
#if __TARGET_TOFINO__ == 2
#include <t2na.p4>
#else
#include <tna.p4>
#endif

#include "./headers.p4"
#include "./util.p4"

//+++++++++++++++++++++++++++
// define
//+++++++++++++++++++++++++++

// General
#define SKETCH_BUCKET_LENGTH 2916    // length of Sketch (d) 2^10

// TsTime
typedef bit<16> length_bit_width_t;     // bits width of length
typedef bit<32> time_t;                 // time stamp

// TsSketch
#define RESUBMIT_TYPE 1
typedef bit<16> bucket_t; // type of sketch bucket
typedef bit<16> bridge_t; // type of bridge header

// TsQueue
#define N_QUEUES 1024 // number of queues

// Mirror
#define MIRROR_TYPE 1


// Resubmit for deletion
@flexible
header resub_t{
    length_bit_width_t index0;
    length_bit_width_t index1;
    bucket_t min_value;
}
@pa_container_size("ingress", "ig_md.resub.index0", 16)
@pa_container_size("ingress", "ig_md.resub.index1", 16)
@pa_container_size("ingress", "ig_md.resub.min_value", 32)

// Bridge header
enum bit<8> internal_header_t {
    NONE               = 0x0,
    BRIDGE_HDR         = 0x1
}

@flexible
header internal_h {
    internal_header_t header_type;
}

@flexible
header bridge_h{
    bridge_t max_value;
    bridge_t min_value;
    bridge_t value0;
    bridge_t value1;
    bridge_t value2;
    bridge_t value3;
    bridge_t value4;
    bridge_t value5;
    bridge_t value6;
    bridge_t value7;
    bridge_t mean_value;
    bridge_t sq_mean_value;
}

@flexible
struct metadata_t{
    // resubmit and bridge fields
    resub_t resub;
    bridge_h bri;
    // MirrorId_t ing_mir_ses;

    length_bit_width_t index0; // indicate the TsTime and TsSketch
    length_bit_width_t index1;

    time_t short_timeStamp; // cut the global time stamp to 32 bits(~4s limits)
    bool time_update_result_0; // TsTime0 result(whether its touched the threshold)
    bool time_update_result_1;
    bool update_flag;

    bool flow_matched; 

    bucket_t flow_id;

    // TsQueues

    bucket_t value0;
    bucket_t value1;
    bucket_t value2;
    bucket_t value3;
    bucket_t value4;
    bucket_t value5;
    bucket_t value6;
    bucket_t value7;

    
    // FOR EGRESS PARSER
    internal_h internal_hdr;

    

}   

control TSSKETCH(
        inout metadata_t tsdata,
        inout header_t hdr,
        in ingress_intrinsic_metadata_t ig_intr_md,
        in ingress_intrinsic_metadata_from_parser_t ig_prsr_md,
        inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
        inout ingress_intrinsic_metadata_for_tm_t ig_tm_md){

    Lpf<bucket_t, length_bit_width_t>(N_QUEUES) mean_processor;
    Lpf<bucket_t, length_bit_width_t>(N_QUEUES) sq_mean_processor;

    // TsSketch
    bucket_t min_result;
    bucket_t sketch0_result; // return value of each sketch buckets
    bucket_t sketch1_result;

    //TsQueues

    bucket_t last_value;

    //+++++++++++++++++++++++++++
    // hashings & hash actions
    //+++++++++++++++++++++++++++

    CRCPolynomial<bit<64>>(0x1f0cb4ab9, false, false, false, 0x00, 0x00) poly0;
    Hash<bit<16>>(HashAlgorithm_t.CUSTOM, poly0) hash0;

    CRCPolynomial<bit<64>>(0x17b7138fd, false, false, false, 0x00, 0x00) poly1;
    Hash<bit<16>>(HashAlgorithm_t.CUSTOM, poly1) hash1;

    //+++++++++++++++++++++++++++
    // registers and register actions
    //+++++++++++++++++++++++++++

    // For test

    // Register<int<32>, int<1>>(1) temp1;
    // RegisterAction<int<32>, bit<1>, int<32>> (temp1) update1 = {
    //     void apply(inout int<32> value, out int<32> result) {
    //         value = (int<32>)tsdata.update_flag;
    //         result = value;
    //     }
    // };

    // Timestamp module
    Register<time_t, length_bit_width_t>(SKETCH_BUCKET_LENGTH) TsTime0;
    RegisterAction<time_t, length_bit_width_t, bool> (TsTime0) updateTime0 = {
        void apply(inout time_t value, out bool result) {
            result = false;
            if (tsdata.short_timeStamp - value != 0){
                result = true;
                value = tsdata.short_timeStamp;
            }
        }
    };

    Register<time_t, length_bit_width_t>(SKETCH_BUCKET_LENGTH) TsTime1;
    RegisterAction<time_t, length_bit_width_t, bool> (TsTime1) updateTime1 = {
        void apply(inout time_t value, out bool result) {
            result = false;
            if (tsdata.short_timeStamp - value != 0){
                result = true;
                value = tsdata.short_timeStamp;
            }
        }
    };

    // TsSketch
    Register<bucket_t, length_bit_width_t>(SKETCH_BUCKET_LENGTH) TsSketch0;
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsSketch0) updateSketch0_wo_update = {
        void apply(inout bucket_t value, out bucket_t result) {
            value = value + 1;
            result = value;
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsSketch0) sketch0_del = {
        void apply(inout bucket_t value, out bucket_t result) {
            value = value - tsdata.resub.min_value;
        }
    };

    Register<bucket_t, length_bit_width_t>(SKETCH_BUCKET_LENGTH) TsSketch1;
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsSketch1) updateSketch1_wo_update = {
        void apply(inout bucket_t value, out bucket_t result) {
            value = value + 1;
            result = value;
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsSketch1) sketch1_del = {
        void apply(inout bucket_t value, out bucket_t result) {
            value = value - tsdata.resub.min_value;
        }
    };
    
    //TsQueue
    Register<bucket_t, length_bit_width_t>(N_QUEUES) TsQueue0;
    Register<bucket_t, length_bit_width_t>(N_QUEUES) TsQueue1;
    Register<bucket_t, length_bit_width_t>(N_QUEUES) TsQueue2;
    Register<bucket_t, length_bit_width_t>(N_QUEUES) TsQueue3;
    Register<bucket_t, length_bit_width_t>(N_QUEUES) TsQueue4;
    Register<bucket_t, length_bit_width_t>(N_QUEUES) TsQueue5;
    Register<bucket_t, length_bit_width_t>(N_QUEUES) TsQueue6;
    Register<bucket_t, length_bit_width_t>(N_QUEUES) TsQueue7;
    Register<bucket_t, length_bit_width_t>(N_QUEUES) TsQueue_max;
    Register<bucket_t, length_bit_width_t>(N_QUEUES) TsQueue_min;
    Register<bucket_t, length_bit_width_t>(N_QUEUES) TsQueue_last;
    Register<bucket_t, length_bit_width_t>(N_QUEUES) TsQueue_flow;

    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue0) query0 = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue0) insert0 = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
            value = min_result;
            
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue0) clear0 = {
        void apply(inout bucket_t value, out bucket_t result) {
            value = 0;
        }
    };

    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue1) query1 = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue1) insert1 = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
            value = min_result;
            
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue1) clear1 = {
        void apply(inout bucket_t value, out bucket_t result) {
            value = 0;
        }
    };

    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue2) query2 = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue2) insert2 = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
            value = min_result;
            
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue2) clear2 = {
        void apply(inout bucket_t value, out bucket_t result) {
            value = 0;
        }
    };

    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue3) query3 = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue3) insert3 = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
            value = min_result;
            
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue3) clear3 = {
        void apply(inout bucket_t value, out bucket_t result) {
            value = 0;
        }
    };

    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue4) query4 = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue4) insert4 = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
            value = min_result;
            
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue4) clear4 = {
        void apply(inout bucket_t value, out bucket_t result) {
            value = 0;
        }
    };

    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue5) query5 = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue5) insert5 = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
            value = min_result;
            
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue5) clear5 = {
        void apply(inout bucket_t value, out bucket_t result) {
            value = 0;
        }
    };

    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue6) query6 = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue6) insert6 = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
            value = min_result;
            
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue6) clear6 = {
        void apply(inout bucket_t value, out bucket_t result) {
            value = 0;
        }
    };

    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue7) query7 = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue7) insert7 = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
            value = min_result;
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue7) clear7 = {
        void apply(inout bucket_t value, out bucket_t result) {
            value = 0;
        }
    };

    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue_max) clear_max_register = {
        void apply(inout bucket_t value, out bucket_t result) {
            value = min_result;
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue_max) update_max_value = {
        void apply(inout bucket_t value, out bucket_t result) {
            value = max(value, min_result);
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue_max) query_max_value = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
        }
    };
    
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue_min) clear_min_register = {
        void apply(inout bucket_t value, out bucket_t result) {
            value = min_result;
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue_min) update_min_value = {
        void apply(inout bucket_t value, out bucket_t result) {
            value = min(value, min_result);
        }
    };
    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue_min) query_min_value = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
        }
    };

    RegisterAction<bucket_t, length_bit_width_t, bucket_t> (TsQueue_last) update_last = {
        void apply(inout bucket_t value, out bucket_t result) {
            result = value;
            value = min_result;
        }
    };

    RegisterAction<bucket_t, length_bit_width_t, bool> (TsQueue_flow) ownership_judgement = {
        void apply(inout bucket_t value, out bool result) {
            if(value == hdr.ipv4.src_addr[15:0]){
                result = true;
            }
            else{
                value = hdr.ipv4.src_addr[15:0];
                result = false;
            }
        }
    };



    //+++++++++++++++++++++++++++
    // actions
    //+++++++++++++++++++++++++++


    action getHashing0(){
        //for test
        tsdata.index0 = 0;
        // tsdata.index0 = hash0.get({hdr.ipv4.src_addr, hdr.ipv4.dst_addr, hdr.tcp.src_port, hdr.tcp.dst_port, hdr.ipv4.protocol});
    }

    action getHashing1(){
        //for test
        tsdata.index1 = 0;
        // tsdata.index1 = hash1.get({hdr.ipv4.src_addr, hdr.ipv4.dst_addr});
    }

    action cut_globaltstamp_to_short(){
        // tsdata.short_timeStamp = (bit<32>)ig_prsr_md.global_tstamp[22:20]; // ~1ms 8ms total
        tsdata.short_timeStamp = (bit<32>)ig_prsr_md.global_tstamp[32:30]; // ~1s 8s total
    }


    action updateTsTime0(){
        tsdata.time_update_result_0 = updateTime0.execute(tsdata.index0);
    }

    action updateTsTime1(){
        tsdata.time_update_result_1 = updateTime1.execute(tsdata.index1);
    }

    action set_update_flag(bool value){
        //update_test.execute(0);
        tsdata.update_flag = value;
    }

    action Sketch0_update_action(){
        sketch0_result = updateSketch0_wo_update.execute(tsdata.index0);
    }

    action Sketch1_update_action(){
        sketch1_result = updateSketch1_wo_update.execute(tsdata.index1);
    }

    action query0_action(){
        tsdata.value0 = query0.execute(tsdata.index0);
    }
    action insert0_action(){
        tsdata.value0 = insert0.execute(tsdata.index0);
    }
    action clear0_action(){
        tsdata.value0 = clear0.execute(tsdata.index0);
    }

    action query1_action(){
        tsdata.value1 = query1.execute(tsdata.index0);
    }
    action insert1_action(){
        tsdata.value1 = insert1.execute(tsdata.index0);
    }
    action clear1_action(){
        tsdata.value1 = clear1.execute(tsdata.index0);
    }

    action query2_action(){
        tsdata.value2 = query2.execute(tsdata.index0);
    }
    action insert2_action(){
        tsdata.value2 = insert2.execute(tsdata.index0);
    }
    action clear2_action(){
        tsdata.value2 = clear2.execute(tsdata.index0);
    }

    action query3_action(){
        tsdata.value3 = query3.execute(tsdata.index0);
    }
    action insert3_action(){
        tsdata.value3 = insert3.execute(tsdata.index0);
    }
    action clear3_action(){
        tsdata.value3 = clear3.execute(tsdata.index0);
    }

    action query4_action(){
        tsdata.value4 = query4.execute(tsdata.index0);
    }
    action insert4_action(){
        tsdata.value4 = insert4.execute(tsdata.index0);
    }
    action clear4_action(){
        tsdata.value4 = clear4.execute(tsdata.index0);
    }

    action query5_action(){
        tsdata.value5 = query5.execute(tsdata.index0);
    }
    action insert5_action(){
        tsdata.value5 = insert5.execute(tsdata.index0);
    }
    action clear5_action(){
        tsdata.value5 = clear5.execute(tsdata.index0);
    }

    action query6_action(){
        tsdata.value6 = query6.execute(tsdata.index0);
    }
    action insert6_action(){
        tsdata.value6 = insert6.execute(tsdata.index0);
    }
    action clear6_action(){
        tsdata.value6 = clear6.execute(tsdata.index0);
    }

    action query7_action(){
        tsdata.value7 = query7.execute(tsdata.index0);
    }
    action insert7_action(){
        tsdata.value7 = insert7.execute(tsdata.index0);
    }
    action clear7_action(){
        tsdata.value7 = clear7.execute(tsdata.index0);
    }

    action sketch0_del_action(length_bit_width_t value){
        sketch0_del.execute(value);
    }

    action sketch1_del_action(length_bit_width_t value){
        sketch1_del.execute(value);
    }


    action clear_max_register_action(){
        clear_max_register.execute(tsdata.index0);
    }

    action update_max_value_action(){
        update_max_value.execute(tsdata.index0);
    }

    action query_max_value_action(){
        tsdata.bri.max_value = query_max_value.execute(tsdata.index0);
    }

    action clear_min_register_action(){
        clear_min_register.execute(tsdata.index0);
    }

    action update_min_value_action(){
        update_min_value.execute(tsdata.index0);
    }

    action query_min_value_action(){
        tsdata.bri.min_value = query_min_value.execute(tsdata.index0);
    }

    action insert_last_action(){
        last_value = update_last.execute(tsdata.index0);
    }

    action query0_action_to_bri(){
        tsdata.bri.value0 = query0.execute(tsdata.index0);
    }
    action query1_action_to_bri(){
        tsdata.bri.value1 = query1.execute(tsdata.index0);
    }
    action query2_action_to_bri(){
        tsdata.bri.value2 = query2.execute(tsdata.index0);
    }
    action query3_action_to_bri(){
        tsdata.bri.value3 = query3.execute(tsdata.index0);
    }
    action query4_action_to_bri(){
        tsdata.bri.value4 = query4.execute(tsdata.index0);
    }
    action query5_action_to_bri(){
        tsdata.bri.value5 = query5.execute(tsdata.index0);
    }
    action query6_action_to_bri(){
        tsdata.bri.value6 = query6.execute(tsdata.index0);
    }
    action query7_action_to_bri(){
        tsdata.bri.value7 = query7.execute(tsdata.index0);
    }


    action location_occupied(){
        tsdata.flow_matched = ownership_judgement.execute(tsdata.index0);
    }



    //+++++++++++++++++++++++++++
    // tables
    //+++++++++++++++++++++++++++

    table update_occupied{
        key={
            tsdata.time_update_result_0 : exact;
            tsdata.time_update_result_1 : exact;
        }
        actions={
            set_update_flag;
            @defaultonly NoAction;
        }
        const size = 4;
        const default_action = NoAction();
        const entries={
            (true, true) : set_update_flag(true);
            (true, false) : set_update_flag(true);
            (false, true) : set_update_flag(true);
            (false, false) : set_update_flag(false);
        }
        
    }

    table choose_tsQueue_bucket_0{
        key={
            tsdata.update_flag : exact;
            tsdata.short_timeStamp : ternary;
            tsdata.flow_matched : ternary;
        }
        actions={
            insert0_action;
            query0_action;
            clear0_action;
            @defaultonly NoAction;
        }
        const default_action = NoAction;
        const size = 4;
        const entries={
            (true, 32w0, _)  : insert0_action();
            (true, _, true) : query0_action();
            (true, _, false) : clear0_action();
        }
    }


    table choose_tsQueue_bucket_1{
        key={
            tsdata.update_flag : exact;
            tsdata.short_timeStamp : ternary;
            tsdata.flow_matched : ternary;
        }
        actions={
            insert1_action;
            query1_action;
            clear1_action;
            @defaultonly NoAction;
        }
        const default_action = NoAction;
        const size = 4;
        const entries={
            (true, 32w1, _)  : insert1_action();
            (true, _, true) : query1_action();
            (true, _, false) : clear1_action();
        }
    }

    table choose_tsQueue_bucket_2{
        key={
            tsdata.update_flag : exact;
            tsdata.short_timeStamp : ternary;
            tsdata.flow_matched : ternary;
        }
        actions={
            insert2_action;
            query2_action;
            clear2_action;
            @defaultonly NoAction;
        }
        const default_action = NoAction;
        const size = 4;
        const entries={
            (true, 32w2, _)  : insert2_action();
            (true, _, true) : query2_action();
            (true, _, false) : clear2_action();
        }
    }

    table choose_tsQueue_bucket_3{
        key={
            tsdata.update_flag : exact;
            tsdata.short_timeStamp : ternary;
            tsdata.flow_matched : ternary;
        }
        actions={
            insert3_action;
            query3_action;
            clear3_action;
            @defaultonly NoAction;
        }
        const default_action = NoAction;
        const size = 4;
        const entries={
            (true, 32w3, _)  : insert3_action();
            (true, _, true) : query3_action();
            (true, _, false) : clear3_action();
        }
    }

    table choose_tsQueue_bucket_4{
        key={
            tsdata.update_flag : exact;
            tsdata.short_timeStamp : ternary;
            tsdata.flow_matched : ternary;
        }
        actions={
            insert4_action;
            query4_action;
            clear4_action;
            @defaultonly NoAction;
        }
        const default_action = NoAction;
        const size = 4;
        const entries={
            (true, 32w4, _)  : insert4_action();
            (true, _, true) : query4_action();
            (true, _, false) : clear4_action();
        }
    }

    table choose_tsQueue_bucket_5{
        key={
            tsdata.update_flag : exact;
            tsdata.short_timeStamp : ternary;
            tsdata.flow_matched : ternary;
        }
        actions={
            insert5_action;
            query5_action;
            clear5_action;
            @defaultonly NoAction;
        }
        const default_action = NoAction;
        const size = 4;
        const entries={
            (true, 32w5, _)  : insert5_action();
            (true, _, true) : query5_action();
            (true, _, false) : clear5_action();
        }
    }

    table choose_tsQueue_bucket_6{
        key={
            tsdata.update_flag : exact;
            tsdata.short_timeStamp : ternary;
            tsdata.flow_matched : ternary;
        }
        actions={
            insert6_action;
            query6_action;
            clear6_action;
            @defaultonly NoAction;
        }
        const default_action = NoAction;
        const size = 4;
        const entries={
            (true, 32w6, _)  : insert6_action();
            (true, _, true) : query6_action();
            (true, _, false) : clear6_action();
        }
    }

    table choose_tsQueue_bucket_7{
        key={
            tsdata.update_flag : exact;
            tsdata.short_timeStamp : ternary;
            tsdata.flow_matched : ternary;
        }
        actions={
            insert7_action;
            query7_action;
            clear7_action;
            @defaultonly NoAction;
        }
        const default_action = NoAction;
        const size = 4;
        const entries={
            (true, 32w7, _)  : insert7_action();
            (true, _, true) : query7_action();
            (true, _, false) : clear7_action();
        }
    }

    table keep_tsQueue_max{
        key={
            tsdata.short_timeStamp : exact;
        }
        actions={
            clear_max_register_action;
            update_max_value_action;
            @defaultonly NoAction;
        }
        const default_action = NoAction;
        const size = 8;
        const entries={
            0 : clear_max_register_action();
            1 : update_max_value_action();
            2 : update_max_value_action();
            3 : update_max_value_action();
            4 : update_max_value_action();
            5 : update_max_value_action();
            6 : update_max_value_action();
            7 : update_max_value_action();
        }
    }

    table keep_tsQueue_min{
        key={
            tsdata.short_timeStamp : exact;
        }
        actions={
            clear_min_register_action;
            update_min_value_action;
            @defaultonly NoAction;
        }
        const default_action = NoAction;
        const size = 8;
        const entries={
            0 : clear_min_register_action();
            1 : update_min_value_action();
            2 : update_min_value_action();
            3 : update_min_value_action();
            4 : update_min_value_action();
            5 : update_min_value_action();
            6 : update_min_value_action();
            7 : update_min_value_action();
        }
    }

    bucket_t sq_num;

    action value_sq_action(bucket_t val){
        sq_num = val;
    }

    table value_sq{
        key={
            tsdata.resub.min_value : exact;
        }
        actions={
            value_sq_action;
            @defaultonly NoAction;
        }
        const default_action = NoAction;
        const size = 256;
        const entries={
            0 : value_sq_action(0);
            1 : value_sq_action(1);
            2 : value_sq_action(4);
            3 : value_sq_action(9);
            4 : value_sq_action(16);
            5 : value_sq_action(25);
            6 : value_sq_action(36);
            7 : value_sq_action(49);
            8 : value_sq_action(64);
            9 : value_sq_action(81);
            10 : value_sq_action(100);
            11 : value_sq_action(121);
            12 : value_sq_action(144);
            13 : value_sq_action(169);
            14 : value_sq_action(196);
            15 : value_sq_action(225);
            16 : value_sq_action(256);
            17 : value_sq_action(289);
            18 : value_sq_action(324);
            19 : value_sq_action(361);
            20 : value_sq_action(400);
            21 : value_sq_action(441);
            22 : value_sq_action(484);
            23 : value_sq_action(529);
            24 : value_sq_action(576);
            25 : value_sq_action(625);
            26 : value_sq_action(676);
            27 : value_sq_action(729);
            28 : value_sq_action(784);
            29 : value_sq_action(841);
            30 : value_sq_action(900);
            31 : value_sq_action(961);
            32 : value_sq_action(1024);
            33 : value_sq_action(1089);
            34 : value_sq_action(1156);
            35 : value_sq_action(1225);
            36 : value_sq_action(1296);
            37 : value_sq_action(1369);
            38 : value_sq_action(1444);
            39 : value_sq_action(1521);
            40 : value_sq_action(1600);
            41 : value_sq_action(1681);
            42 : value_sq_action(1764);
            43 : value_sq_action(1849);
            44 : value_sq_action(1936);
            45 : value_sq_action(2025);
            46 : value_sq_action(2116);
            47 : value_sq_action(2209);
            48 : value_sq_action(2304);
            49 : value_sq_action(2401);
            50 : value_sq_action(2500);
            51 : value_sq_action(2601);
            52 : value_sq_action(2704);
            53 : value_sq_action(2809);
            54 : value_sq_action(2916);
            55 : value_sq_action(3025);
            56 : value_sq_action(3136);
            57 : value_sq_action(3249);
            58 : value_sq_action(3364);
            59 : value_sq_action(3481);
            60 : value_sq_action(3600);
            61 : value_sq_action(3721);
            62 : value_sq_action(3844);
            63 : value_sq_action(3969);
            64 : value_sq_action(4096);
            65 : value_sq_action(4225);
            66 : value_sq_action(4356);
            67 : value_sq_action(4489);
            68 : value_sq_action(4624);
            69 : value_sq_action(4761);
            70 : value_sq_action(4900);
            71 : value_sq_action(5041);
            72 : value_sq_action(5184);
            73 : value_sq_action(5329);
            74 : value_sq_action(5476);
            75 : value_sq_action(5625);
            76 : value_sq_action(5776);
            77 : value_sq_action(5929);
            78 : value_sq_action(6084);
            79 : value_sq_action(6241);
            80 : value_sq_action(6400);
            81 : value_sq_action(6561);
            82 : value_sq_action(6724);
            83 : value_sq_action(6889);
            84 : value_sq_action(7056);
            85 : value_sq_action(7225);
            86 : value_sq_action(7396);
            87 : value_sq_action(7569);
            88 : value_sq_action(7744);
            89 : value_sq_action(7921);
            90 : value_sq_action(8100);
            91 : value_sq_action(8281);
            92 : value_sq_action(8464);
            93 : value_sq_action(8649);
            94 : value_sq_action(8836);
            95 : value_sq_action(9025);
            96 : value_sq_action(9216);
            97 : value_sq_action(9409);
            98 : value_sq_action(9604);
            99 : value_sq_action(9801);
            100 : value_sq_action(10000);
            101 : value_sq_action(10201);
            102 : value_sq_action(10404);
            103 : value_sq_action(10609);
            104 : value_sq_action(10816);
            105 : value_sq_action(11025);
            106 : value_sq_action(11236);
            107 : value_sq_action(11449);
            108 : value_sq_action(11664);
            109 : value_sq_action(11881);
            110 : value_sq_action(12100);
            111 : value_sq_action(12321);
            112 : value_sq_action(12544);
            113 : value_sq_action(12769);
            114 : value_sq_action(12996);
            115 : value_sq_action(13225);
            116 : value_sq_action(13456);
            117 : value_sq_action(13689);
            118 : value_sq_action(13924);
            119 : value_sq_action(14161);
            120 : value_sq_action(14400);
            121 : value_sq_action(14641);
            122 : value_sq_action(14884);
            123 : value_sq_action(15129);
            124 : value_sq_action(15376);
            125 : value_sq_action(15625);
            126 : value_sq_action(15876);
            127 : value_sq_action(16129);
            128 : value_sq_action(16384);
            129 : value_sq_action(16641);
            130 : value_sq_action(16900);
            131 : value_sq_action(17161);
            132 : value_sq_action(17424);
            133 : value_sq_action(17689);
            134 : value_sq_action(17956);
            135 : value_sq_action(18225);
            136 : value_sq_action(18496);
            137 : value_sq_action(18769);
            138 : value_sq_action(19044);
            139 : value_sq_action(19321);
            140 : value_sq_action(19600);
            141 : value_sq_action(19881);
            142 : value_sq_action(20164);
            143 : value_sq_action(20449);
            144 : value_sq_action(20736);
            145 : value_sq_action(21025);
            146 : value_sq_action(21316);
            147 : value_sq_action(21609);
            148 : value_sq_action(21904);
            149 : value_sq_action(22201);
            150 : value_sq_action(22500);
            151 : value_sq_action(22801);
            152 : value_sq_action(23104);
            153 : value_sq_action(23409);
            154 : value_sq_action(23716);
            155 : value_sq_action(24025);
            156 : value_sq_action(24336);
            157 : value_sq_action(24649);
            158 : value_sq_action(24964);
            159 : value_sq_action(25281);
            160 : value_sq_action(25600);
            161 : value_sq_action(25921);
            162 : value_sq_action(26244);
            163 : value_sq_action(26569);
            164 : value_sq_action(26896);
            165 : value_sq_action(27225);
            166 : value_sq_action(27556);
            167 : value_sq_action(27889);
            168 : value_sq_action(28224);
            169 : value_sq_action(28561);
            170 : value_sq_action(28900);
            171 : value_sq_action(29241);
            172 : value_sq_action(29584);
            173 : value_sq_action(29929);
            174 : value_sq_action(30276);
            175 : value_sq_action(30625);
            176 : value_sq_action(30976);
            177 : value_sq_action(31329);
            178 : value_sq_action(31684);
            179 : value_sq_action(32041);
            180 : value_sq_action(32400);
            181 : value_sq_action(32761);
            182 : value_sq_action(33124);
            183 : value_sq_action(33489);
            184 : value_sq_action(33856);
            185 : value_sq_action(34225);
            186 : value_sq_action(34596);
            187 : value_sq_action(34969);
            188 : value_sq_action(35344);
            189 : value_sq_action(35721);
            190 : value_sq_action(36100);
            191 : value_sq_action(36481);
            192 : value_sq_action(36864);
            193 : value_sq_action(37249);
            194 : value_sq_action(37636);
            195 : value_sq_action(38025);
            196 : value_sq_action(38416);
            197 : value_sq_action(38809);
            198 : value_sq_action(39204);
            199 : value_sq_action(39601);
            200 : value_sq_action(40000);
            201 : value_sq_action(40401);
            202 : value_sq_action(40804);
            203 : value_sq_action(41209);
            204 : value_sq_action(41616);
            205 : value_sq_action(42025);
            206 : value_sq_action(42436);
            207 : value_sq_action(42849);
            208 : value_sq_action(43264);
            209 : value_sq_action(43681);
            210 : value_sq_action(44100);
            211 : value_sq_action(44521);
            212 : value_sq_action(44944);
            213 : value_sq_action(45369);
            214 : value_sq_action(45796);
            215 : value_sq_action(46225);
            216 : value_sq_action(46656);
            217 : value_sq_action(47089);
            218 : value_sq_action(47524);
            219 : value_sq_action(47961);
            220 : value_sq_action(48400);
            221 : value_sq_action(48841);
            222 : value_sq_action(49284);
            223 : value_sq_action(49729);
            224 : value_sq_action(50176);
            225 : value_sq_action(50625);
            226 : value_sq_action(51076);
            227 : value_sq_action(51529);
            228 : value_sq_action(51984);
            229 : value_sq_action(52441);
            230 : value_sq_action(52900);
            231 : value_sq_action(53361);
            232 : value_sq_action(53824);
            233 : value_sq_action(54289);
            234 : value_sq_action(54756);
            235 : value_sq_action(55225);
            236 : value_sq_action(55696);
            237 : value_sq_action(56169);
            238 : value_sq_action(56644);
            239 : value_sq_action(57121);
            240 : value_sq_action(57600);
            241 : value_sq_action(58081);
            242 : value_sq_action(58564);
            243 : value_sq_action(59049);
            244 : value_sq_action(59536);
            245 : value_sq_action(60025);
            246 : value_sq_action(60516);
            247 : value_sq_action(61009);
            248 : value_sq_action(61504);
            249 : value_sq_action(62001);
            250 : value_sq_action(62500);
            251 : value_sq_action(63001);
            252 : value_sq_action(63504);
            253 : value_sq_action(64009);
            254 : value_sq_action(64516);
            255 : value_sq_action(65025);
        }
    }


    
    Register<bit<32>, bit<1>>(1) temp_2;
    RegisterAction<bit<32>, bit<1>, bit<32>> (temp_2) test_2={
        void apply(inout bit<32> value, out bit<32> result) {
            value = value + 1;
            result = value;
        }
    };


    
    
    apply{

        // --------------------------------------------------------------
        //     TsSketch & TsQueues
        // --------------------------------------------------------------

        // Hashing
        

        if(ig_intr_md.resubmit_flag == 0){
            // tsdata.flow_id.src_addr = hdr.ipv4.src_addr;

            getHashing0();
            getHashing1();
            cut_globaltstamp_to_short();

            Sketch0_update_action();
            Sketch1_update_action();
            // Get mininum value
            min_result = min(sketch0_result, sketch1_result);

            // Update the TsTime registers
            updateTsTime0();
            updateTsTime1();

            // get the update sign
            update_occupied.apply(); 
            location_occupied();

            //
            

            // Conditionally placing a value into TsQueue

            choose_tsQueue_bucket_0.apply();
            choose_tsQueue_bucket_1.apply();
            choose_tsQueue_bucket_2.apply();
            choose_tsQueue_bucket_3.apply();
            choose_tsQueue_bucket_4.apply();
            choose_tsQueue_bucket_5.apply();
            choose_tsQueue_bucket_6.apply();
            choose_tsQueue_bucket_7.apply();

            
            

            // resubmiting this packet for deletion
            if(tsdata.update_flag == true){
                // insert_last_action();

                // Conditionally keep min/max value
                keep_tsQueue_max.apply();
                keep_tsQueue_min.apply(); 

                ig_dprsr_md.resubmit_type = RESUBMIT_TYPE;
                tsdata.resub.index0 = tsdata.index0;
                tsdata.resub.index1 = tsdata.index1;
                tsdata.resub.min_value = min_result;
            }
            else{
                tsdata.internal_hdr.setInvalid();
                tsdata.bri.setInvalid();
                ig_tm_md.bypass_egress = 1w1;
            }
            


        }
        else{
            test_2.execute(0);
            // only way to go to egress
            tsdata.bri.setValid();
            sketch0_del_action(tsdata.resub.index0);
            sketch1_del_action(tsdata.resub.index1);

            value_sq.apply();
            tsdata.bri.mean_value = mean_processor.execute(tsdata.resub.min_value, 0);
            tsdata.bri.sq_mean_value = sq_mean_processor.execute(sq_num, 0);

            
            query0_action_to_bri();
            query1_action_to_bri();
            query2_action_to_bri();
            query3_action_to_bri();
            query4_action_to_bri();
            query5_action_to_bri();
            query6_action_to_bri();
            query7_action_to_bri();

            query_max_value_action();
            query_min_value_action();

            tsdata.internal_hdr.setValid(); // 这里必须setValid, 原因是下面只是将 header_type setVliad, 然而这个 internal_hdr 结构体没有.
            tsdata.internal_hdr.header_type = internal_header_t.BRIDGE_HDR;
        }



    }
}

// --------------------------------------------------------------
//     Ingress Control
// --------------------------------------------------------------

control SwitchIngress(
        inout header_t hdr,
        inout metadata_t ig_md,
        in ingress_intrinsic_metadata_t ig_intr_md,
        in ingress_intrinsic_metadata_from_parser_t ig_prsr_md,
        inout ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md,
        inout ingress_intrinsic_metadata_for_tm_t ig_tm_md) {


    Register<bit<32>, bit<1>>(1) temp;
    RegisterAction<bit<32>, bit<1>, bit<32>> (temp) update={
        void apply(inout bit<32> value, out bit<32> result) {
            value = (bit<32>)value + 1;
            result = value;
        }
    };
    action test_1(){
        update.execute(0);
    }

    action dmac_action(bit<9> port){
        ig_tm_md.ucast_egress_port = port;
    }
    action d_action(){
        ig_tm_md.ucast_egress_port = 184;
    }

    table dmac{
        key={
            ig_intr_md.ingress_port : exact;
        }
        actions={
            dmac_action;
            d_action;
        }
        const size = 4;
        default_action = d_action;
        const entries={
            176 : dmac_action(184);
            184 : dmac_action(176);
        }
    }

    TSSKETCH() tsSketch;

    apply{
        dmac.apply();
        test_1();

        if(ig_intr_md.ingress_port != 184){ 
            // 只处理TCP/UDP包
            if(hdr.ipv4.isValid() && (hdr.tcp.isValid() || hdr.udp.isValid())){
                
                tsSketch.apply(ig_md, hdr, ig_intr_md, ig_prsr_md, ig_dprsr_md, ig_tm_md);
            }
            else{
                // ARP、ICMP等其他协议直接转发
                ig_md.internal_hdr.setInvalid();
                ig_md.bri.setInvalid();
                ig_tm_md.bypass_egress = 1w1;
            }
        }
        else{
            ig_md.internal_hdr.setInvalid();
            ig_md.bri.setInvalid();
            ig_tm_md.bypass_egress = 1w1;
        }
    }
}

// --------------------------------------------------------------
//     Ingress Parser
// --------------------------------------------------------------


// parser SwitchIngressParser(
//         packet_in pkt,
//         out header_t hdr,
//         out metadata_t ig_md,
//         out ingress_intrinsic_metadata_t ig_intr_md) {

//     state start {
//         ig_md.internal_hdr.setValid();
//         ig_md.internal_hdr.header_type = internal_header_t.NONE;
//         ig_md.bri.setInvalid();
        
//         pkt.extract(ig_intr_md);
//         transition select(ig_intr_md.resubmit_flag) {
//             0 : parse_ethernet;
//             1 : parse_resubmit;
//             default : accept;
//         }
//     }

//     state parse_resubmit{
//         pkt.extract(ig_md.resub);
//         transition parse_ethernet_end;
//     }

//     state parse_ethernet {
//         pkt.advance(PORT_METADATA_SIZE);
//         pkt.extract(hdr.ethernet);
//         transition accept;
//     }

//     state parse_ethernet_end{
//         pkt.extract(hdr.ethernet);
//         transition accept;
//     }

// }

parser SwitchIngressParser(
        packet_in pkt,
        out header_t hdr,
        out metadata_t ig_md,
        out ingress_intrinsic_metadata_t ig_intr_md) {

    state start {
        // ig_md.internal_hdr.setValid();
        // ig_md.internal_hdr.header_type = internal_header_t.NONE;
        // ig_md.bri.setInvalid();
        
        pkt.extract(ig_intr_md);
        transition select(ig_intr_md.resubmit_flag) {
            0 : skip_port_metadata;
            1 : parse_resubmit;
            default : accept;
        }
    }

    state parse_resubmit{
        ig_md.resub = pkt.lookahead<resub_t>();
        pkt.advance(PORT_METADATA_SIZE);
        transition parse_ethernet;
    }

    state skip_port_metadata {
        pkt.advance(PORT_METADATA_SIZE);
        transition parse_ethernet;
    }

    state parse_ethernet {
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            0x0800: parse_ipv4;   // IPv4
            0x0806: parse_arp;    // ARP
            default: accept;
        }
    }

    state parse_arp {
        pkt.extract(hdr.arp);  // 需要定义ARP头
        transition accept;
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            6: parse_tcp;   // TCP
            17: parse_udp;  // UDP
            default: accept;
        }
    }

    state parse_tcp {
        pkt.extract(hdr.tcp);
        transition accept;
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        transition accept;
    }

}


// --------------------------------------------------------------
//     Ingress Deparser
// --------------------------------------------------------------

control SwitchIngressDeparser(
        packet_out pkt,
        inout header_t hdr,
        in metadata_t ig_md,
        in ingress_intrinsic_metadata_for_deparser_t ig_dprsr_md) {

    Resubmit() resubmit;

    apply {
        
        if(ig_dprsr_md.resubmit_type == RESUBMIT_TYPE){
            resubmit.emit(ig_md.resub);
        }
        pkt.emit(ig_md.internal_hdr);
        pkt.emit(ig_md.bri);

        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.arp); 
        pkt.emit(hdr.ipv4);
        pkt.emit(hdr.tcp);
        pkt.emit(hdr.udp);
    }
}


// --------------------------------------------------------------
//     Egress Parser
// --------------------------------------------------------------

// parser SwitchEgressParser(
//         packet_in pkt,
//         out header_t hdr,
//         out metadata_t eg_md,
//         out egress_intrinsic_metadata_t eg_intr_md){
    
//     state start{
//         pkt.extract(eg_intr_md);
//         transition parse_internal_hdr;
//     }

//     state parse_internal_hdr{
//         pkt.extract(eg_md.internal_hdr);
//         eg_md.bri.setInvalid();
//         transition select(eg_md.internal_hdr.header_type) {
//             internal_header_t.NONE: parse_ethernet;
//             internal_header_t.BRIDGE_HDR: parse_bridge_hdr;
//             default: parse_ethernet;
//         }
//     }

//     state parse_bridge_hdr{
//         pkt.extract(eg_md.bri);
//         transition parse_ethernet;
//     }

//     state parse_ethernet{
//         pkt.extract(hdr.ethernet);
//         transition accept;
//     }

    
// }

parser SwitchEgressParser(
        packet_in pkt,
        out header_t hdr,
        out metadata_t eg_md,
        out egress_intrinsic_metadata_t eg_intr_md){
    
    state start{
        pkt.extract(eg_intr_md);
        transition parse_internal_hdr;
    }

    state parse_internal_hdr{
        pkt.extract(eg_md.internal_hdr);
        // eg_md.bri.setInvalid();
        transition select(eg_md.internal_hdr.header_type) {
            internal_header_t.NONE: parse_ethernet;
            internal_header_t.BRIDGE_HDR: parse_bridge_hdr;
            default: parse_ethernet;
        }
    }

    state parse_bridge_hdr{
        pkt.extract(eg_md.bri);
        transition parse_ethernet;
    }

    state parse_ethernet{
        pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type) {
            0x0800: parse_ipv4;   // IPv4
            0x0806: parse_arp;    // ARP
            default: accept;
        }
    }

    state parse_arp {
        pkt.extract(hdr.arp);
        transition accept;
    }

    state parse_ipv4 {
        pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.protocol) {
            6: parse_tcp;   // TCP
            17: parse_udp;  // UDP
            default: accept;
        }
    }

    state parse_tcp {
        pkt.extract(hdr.tcp);
        transition accept;
    }

    state parse_udp {
        pkt.extract(hdr.udp);
        transition accept;
    }
}

// --------------------------------------------------------------
//     Egress Control
// --------------------------------------------------------------

control SwitchEgress(
        inout header_t hdr,
        inout metadata_t eg_md,
        in    egress_intrinsic_metadata_t                 eg_intr_md,
        in    egress_intrinsic_metadata_from_parser_t     eg_prsr_md,
        inout egress_intrinsic_metadata_for_deparser_t    eg_dprsr_md,
        inout egress_intrinsic_metadata_for_output_port_t eg_oport_md){


    // FOR EGRESS 

    bucket_t sq_value0;
    bucket_t sq_value1;
    bucket_t sq_value2;
    bucket_t sq_value3;
    bucket_t sq_value4;
    bucket_t sq_value5;
    bucket_t sq_value6;
    bucket_t sq_value7;

    bucket_t sum0;
    bucket_t sum1;
    bucket_t sum2;
    bucket_t sum3;
    bucket_t sum0_1;
    bucket_t sum2_3;
    bucket_t sum;

    bucket_t sq_sum0;
    bucket_t sq_sum1;
    bucket_t sq_sum2;
    bucket_t sq_sum3;
    bucket_t sq_sum0_1;
    bucket_t sq_sum2_3;
    bucket_t sq_sum;

    bucket_t mean_value_sq;  // mean first, then square
    bucket_t sq_mean_value;  // square first, then mean

    bucket_t std;

    bucket_t upper_limit;
    bucket_t lower_limit;

    bucket_t feature1;
    bucket_t feature2;
    bucket_t feature3;
    bucket_t feature4;
    bucket_t feature5;
    bucket_t feature6;
    bucket_t feature7;
    bucket_t feature8;

    bucket_t detection_result;

    // ---------------------------------------------------------
    // Registers
    // ---------------------------------------------------------

    Register<bit<32>, bit<1>>(1) eg_temp_1;
    RegisterAction<bit<32>, bit<1>, bit<32>> (eg_temp_1) egress_test_1_ra={
        void apply(inout bit<32> value, out bit<32> result) {
            value = (bit<32>) sum;
            result = value;
        }
    };

    Register<bit<32>, bit<1>>(1) eg_temp_2;
    RegisterAction<bit<32>, bit<1>, bit<32>> (eg_temp_2) egress_test_2_ra={
        void apply(inout bit<32> value, out bit<32> result) {
            value = (bit<32>) eg_md.bri.max_value;
            result = value;
        }
    };

    Register<bit<32>, bit<1>>(1) eg_temp_3;
    RegisterAction<bit<32>, bit<1>, bit<32>> (eg_temp_3) egress_test_3_ra={
        void apply(inout bit<32> value, out bit<32> result) {
            value = (bit<32>)eg_md.bri.mean_value;
            result = value;
        }
    };

    Register<bit<32>, bit<1>>(1) eg_temp_4;
    RegisterAction<bit<32>, bit<1>, bit<32>> (eg_temp_4) egress_test_4_ra={
        void apply(inout bit<32> value, out bit<32> result) {
            value = (bit<32>)std;
            result = value;
        }
    };

    Register<bit<32>, bit<1>>(1) eg_temp_5;
    RegisterAction<bit<32>, bit<1>, bit<32>> (eg_temp_5) egress_test_5_ra={
        void apply(inout bit<32> value, out bit<32> result) {
            value = (bit<32>)detection_result;
            result = value;
        }
    };

    // MathUnit
    // Register<bucket_t, bit<1>>(1) mathunit_reg;
    // RegisterAction<bucket_t, bit<1>, bucket_t> (mathunit_reg) sqrt_ra={
    //     void apply(inout bucket_t value, out bucket_t result) {
    //         value = sqrt.execute(std);
    //         result = value;
    //     }
    // };

    // ---------------------------------------------------------
    // Actions
    // ---------------------------------------------------------

    action egress_test_1(){
        egress_test_1_ra.execute(0);
    }

    action egress_test_2(){
        egress_test_2_ra.execute(0);
    }

    action egress_test_3(){
        egress_test_3_ra.execute(0);
    }

    action egress_test_4(){
        egress_test_4_ra.execute(0);
    }

    action egress_test_5(){
        egress_test_5_ra.execute(0);
    }


    action return_mean_value_sq(bucket_t val){
        mean_value_sq = val;
    }

    action get_std(){
        std = eg_md.bri.sq_mean_value |-| mean_value_sq;
    }

    action layer1(){
        sum0 = eg_md.bri.value0 + eg_md.bri.value1;
        sum1 = eg_md.bri.value2 + eg_md.bri.value3;
        sum2 = eg_md.bri.value4 + eg_md.bri.value5;
        sum3 = eg_md.bri.value6 + eg_md.bri.value7;
    }

    action layer2(){
        sum0_1 = sum0 + sum1;
        sum2_3 = sum2 + sum3;
    }

    action layer3(){
        sum = sum0_1 + sum2_3;
    }

    // ---------------------------------------------------------
    // Tables
    // ---------------------------------------------------------

    table get_mean_sq{
        key={
            eg_md.bri.mean_value : exact;
        }
        actions={
            return_mean_value_sq;
            @defaultonly NoAction;
        }
        const size = 256;
        const entries={
            0 : return_mean_value_sq(0);
            1 : return_mean_value_sq(1);
            2 : return_mean_value_sq(4);
            3 : return_mean_value_sq(9);
            4 : return_mean_value_sq(16);
            5 : return_mean_value_sq(25);
            6 : return_mean_value_sq(36);
            7 : return_mean_value_sq(49);
            8 : return_mean_value_sq(64);
            9 : return_mean_value_sq(81);
            10 : return_mean_value_sq(100);
            11 : return_mean_value_sq(121);
            12 : return_mean_value_sq(144);
            13 : return_mean_value_sq(169);
            14 : return_mean_value_sq(196);
            15 : return_mean_value_sq(225);
            16 : return_mean_value_sq(256);
            17 : return_mean_value_sq(289);
            18 : return_mean_value_sq(324);
            19 : return_mean_value_sq(361);
            20 : return_mean_value_sq(400);
            21 : return_mean_value_sq(441);
            22 : return_mean_value_sq(484);
            23 : return_mean_value_sq(529);
            24 : return_mean_value_sq(576);
            25 : return_mean_value_sq(625);
            26 : return_mean_value_sq(676);
            27 : return_mean_value_sq(729);
            28 : return_mean_value_sq(784);
            29 : return_mean_value_sq(841);
            30 : return_mean_value_sq(900);
            31 : return_mean_value_sq(961);
            32 : return_mean_value_sq(1024);
            33 : return_mean_value_sq(1089);
            34 : return_mean_value_sq(1156);
            35 : return_mean_value_sq(1225);
            36 : return_mean_value_sq(1296);
            37 : return_mean_value_sq(1369);
            38 : return_mean_value_sq(1444);
            39 : return_mean_value_sq(1521);
            40 : return_mean_value_sq(1600);
            41 : return_mean_value_sq(1681);
            42 : return_mean_value_sq(1764);
            43 : return_mean_value_sq(1849);
            44 : return_mean_value_sq(1936);
            45 : return_mean_value_sq(2025);
            46 : return_mean_value_sq(2116);
            47 : return_mean_value_sq(2209);
            48 : return_mean_value_sq(2304);
            49 : return_mean_value_sq(2401);
            50 : return_mean_value_sq(2500);
            51 : return_mean_value_sq(2601);
            52 : return_mean_value_sq(2704);
            53 : return_mean_value_sq(2809);
            54 : return_mean_value_sq(2916);
            55 : return_mean_value_sq(3025);
            56 : return_mean_value_sq(3136);
            57 : return_mean_value_sq(3249);
            58 : return_mean_value_sq(3364);
            59 : return_mean_value_sq(3481);
            60 : return_mean_value_sq(3600);
            61 : return_mean_value_sq(3721);
            62 : return_mean_value_sq(3844);
            63 : return_mean_value_sq(3969);
            64 : return_mean_value_sq(4096);
            65 : return_mean_value_sq(4225);
            66 : return_mean_value_sq(4356);
            67 : return_mean_value_sq(4489);
            68 : return_mean_value_sq(4624);
            69 : return_mean_value_sq(4761);
            70 : return_mean_value_sq(4900);
            71 : return_mean_value_sq(5041);
            72 : return_mean_value_sq(5184);
            73 : return_mean_value_sq(5329);
            74 : return_mean_value_sq(5476);
            75 : return_mean_value_sq(5625);
            76 : return_mean_value_sq(5776);
            77 : return_mean_value_sq(5929);
            78 : return_mean_value_sq(6084);
            79 : return_mean_value_sq(6241);
            80 : return_mean_value_sq(6400);
            81 : return_mean_value_sq(6561);
            82 : return_mean_value_sq(6724);
            83 : return_mean_value_sq(6889);
            84 : return_mean_value_sq(7056);
            85 : return_mean_value_sq(7225);
            86 : return_mean_value_sq(7396);
            87 : return_mean_value_sq(7569);
            88 : return_mean_value_sq(7744);
            89 : return_mean_value_sq(7921);
            90 : return_mean_value_sq(8100);
            91 : return_mean_value_sq(8281);
            92 : return_mean_value_sq(8464);
            93 : return_mean_value_sq(8649);
            94 : return_mean_value_sq(8836);
            95 : return_mean_value_sq(9025);
            96 : return_mean_value_sq(9216);
            97 : return_mean_value_sq(9409);
            98 : return_mean_value_sq(9604);
            99 : return_mean_value_sq(9801);
            100 : return_mean_value_sq(10000);
            101 : return_mean_value_sq(10201);
            102 : return_mean_value_sq(10404);
            103 : return_mean_value_sq(10609);
            104 : return_mean_value_sq(10816);
            105 : return_mean_value_sq(11025);
            106 : return_mean_value_sq(11236);
            107 : return_mean_value_sq(11449);
            108 : return_mean_value_sq(11664);
            109 : return_mean_value_sq(11881);
            110 : return_mean_value_sq(12100);
            111 : return_mean_value_sq(12321);
            112 : return_mean_value_sq(12544);
            113 : return_mean_value_sq(12769);
            114 : return_mean_value_sq(12996);
            115 : return_mean_value_sq(13225);
            116 : return_mean_value_sq(13456);
            117 : return_mean_value_sq(13689);
            118 : return_mean_value_sq(13924);
            119 : return_mean_value_sq(14161);
            120 : return_mean_value_sq(14400);
            121 : return_mean_value_sq(14641);
            122 : return_mean_value_sq(14884);
            123 : return_mean_value_sq(15129);
            124 : return_mean_value_sq(15376);
            125 : return_mean_value_sq(15625);
            126 : return_mean_value_sq(15876);
            127 : return_mean_value_sq(16129);
            128 : return_mean_value_sq(16384);
            129 : return_mean_value_sq(16641);
            130 : return_mean_value_sq(16900);
            131 : return_mean_value_sq(17161);
            132 : return_mean_value_sq(17424);
            133 : return_mean_value_sq(17689);
            134 : return_mean_value_sq(17956);
            135 : return_mean_value_sq(18225);
            136 : return_mean_value_sq(18496);
            137 : return_mean_value_sq(18769);
            138 : return_mean_value_sq(19044);
            139 : return_mean_value_sq(19321);
            140 : return_mean_value_sq(19600);
            141 : return_mean_value_sq(19881);
            142 : return_mean_value_sq(20164);
            143 : return_mean_value_sq(20449);
            144 : return_mean_value_sq(20736);
            145 : return_mean_value_sq(21025);
            146 : return_mean_value_sq(21316);
            147 : return_mean_value_sq(21609);
            148 : return_mean_value_sq(21904);
            149 : return_mean_value_sq(22201);
            150 : return_mean_value_sq(22500);
            151 : return_mean_value_sq(22801);
            152 : return_mean_value_sq(23104);
            153 : return_mean_value_sq(23409);
            154 : return_mean_value_sq(23716);
            155 : return_mean_value_sq(24025);
            156 : return_mean_value_sq(24336);
            157 : return_mean_value_sq(24649);
            158 : return_mean_value_sq(24964);
            159 : return_mean_value_sq(25281);
            160 : return_mean_value_sq(25600);
            161 : return_mean_value_sq(25921);
            162 : return_mean_value_sq(26244);
            163 : return_mean_value_sq(26569);
            164 : return_mean_value_sq(26896);
            165 : return_mean_value_sq(27225);
            166 : return_mean_value_sq(27556);
            167 : return_mean_value_sq(27889);
            168 : return_mean_value_sq(28224);
            169 : return_mean_value_sq(28561);
            170 : return_mean_value_sq(28900);
            171 : return_mean_value_sq(29241);
            172 : return_mean_value_sq(29584);
            173 : return_mean_value_sq(29929);
            174 : return_mean_value_sq(30276);
            175 : return_mean_value_sq(30625);
            176 : return_mean_value_sq(30976);
            177 : return_mean_value_sq(31329);
            178 : return_mean_value_sq(31684);
            179 : return_mean_value_sq(32041);
            180 : return_mean_value_sq(32400);
            181 : return_mean_value_sq(32761);
            182 : return_mean_value_sq(33124);
            183 : return_mean_value_sq(33489);
            184 : return_mean_value_sq(33856);
            185 : return_mean_value_sq(34225);
            186 : return_mean_value_sq(34596);
            187 : return_mean_value_sq(34969);
            188 : return_mean_value_sq(35344);
            189 : return_mean_value_sq(35721);
            190 : return_mean_value_sq(36100);
            191 : return_mean_value_sq(36481);
            192 : return_mean_value_sq(36864);
            193 : return_mean_value_sq(37249);
            194 : return_mean_value_sq(37636);
            195 : return_mean_value_sq(38025);
            196 : return_mean_value_sq(38416);
            197 : return_mean_value_sq(38809);
            198 : return_mean_value_sq(39204);
            199 : return_mean_value_sq(39601);
            200 : return_mean_value_sq(40000);
            201 : return_mean_value_sq(40401);
            202 : return_mean_value_sq(40804);
            203 : return_mean_value_sq(41209);
            204 : return_mean_value_sq(41616);
            205 : return_mean_value_sq(42025);
            206 : return_mean_value_sq(42436);
            207 : return_mean_value_sq(42849);
            208 : return_mean_value_sq(43264);
            209 : return_mean_value_sq(43681);
            210 : return_mean_value_sq(44100);
            211 : return_mean_value_sq(44521);
            212 : return_mean_value_sq(44944);
            213 : return_mean_value_sq(45369);
            214 : return_mean_value_sq(45796);
            215 : return_mean_value_sq(46225);
            216 : return_mean_value_sq(46656);
            217 : return_mean_value_sq(47089);
            218 : return_mean_value_sq(47524);
            219 : return_mean_value_sq(47961);
            220 : return_mean_value_sq(48400);
            221 : return_mean_value_sq(48841);
            222 : return_mean_value_sq(49284);
            223 : return_mean_value_sq(49729);
            224 : return_mean_value_sq(50176);
            225 : return_mean_value_sq(50625);
            226 : return_mean_value_sq(51076);
            227 : return_mean_value_sq(51529);
            228 : return_mean_value_sq(51984);
            229 : return_mean_value_sq(52441);
            230 : return_mean_value_sq(52900);
            231 : return_mean_value_sq(53361);
            232 : return_mean_value_sq(53824);
            233 : return_mean_value_sq(54289);
            234 : return_mean_value_sq(54756);
            235 : return_mean_value_sq(55225);
            236 : return_mean_value_sq(55696);
            237 : return_mean_value_sq(56169);
            238 : return_mean_value_sq(56644);
            239 : return_mean_value_sq(57121);
            240 : return_mean_value_sq(57600);
            241 : return_mean_value_sq(58081);
            242 : return_mean_value_sq(58564);
            243 : return_mean_value_sq(59049);
            244 : return_mean_value_sq(59536);
            245 : return_mean_value_sq(60025);
            246 : return_mean_value_sq(60516);
            247 : return_mean_value_sq(61009);
            248 : return_mean_value_sq(61504);
            249 : return_mean_value_sq(62001);
            250 : return_mean_value_sq(62500);
            251 : return_mean_value_sq(63001);
            252 : return_mean_value_sq(63504);
            253 : return_mean_value_sq(64009);
            254 : return_mean_value_sq(64516);
            255 : return_mean_value_sq(65025);

        }
    }

    action _sum_ass(bit<16> input){
        feature1 = input;
    }
    table get_feature1{
        key={
            sum : range;
        }
        actions={
            _sum_ass;
        }
        const size = 8;
        const entries={
            0..475 : _sum_ass(0);
            476..6443 : _sum_ass(1);
            6444..65535 : _sum_ass(2);
        }
    }


    action _mean_ass(bit<16> input){
        feature2 = input;
    }
    table get_feature2{
        key={
            eg_md.bri.mean_value : range;
        }
        actions={
            _mean_ass;
        }
        const size = 8;
        const entries={
            0..111 : _mean_ass(0);
            112..1134 : _mean_ass(1);
            1135..65535 : _mean_ass(2);
        }
    }


    action _min_ass(bit<16> input){
        feature3 = input;
    }
    table get_feature3{
        key={
            eg_md.bri.min_value : range;
        }
        actions={
            _min_ass;
        }
        const size = 8;
        const entries={
            0..71 : _min_ass(0);
            72..409 : _min_ass(1);
            410..65535 : _min_ass(2);
        }
    }


    action _max_ass(bit<16> input){
        feature4 = input;
    }
    table get_feature4{
        key={
            eg_md.bri.max_value : range;
        }
        actions={
            _max_ass;
        }
        const size = 8;
        const entries={
            0..544 : _max_ass(0);
            545..65535 : _max_ass(1);
        }
    }


    action _var_ass(bit<16> input){
        feature5 = input;
    }
    table get_feature5{
        key={
            std : range;
        }
        actions={
            _var_ass;
        }
        const size = 8;
        const entries={
            0..12122 : _var_ass(0);
            12123..65535 : _var_ass(1);
        }
    }
    

    action _ttl_last_ass(bit<16> input){
        feature6 = input;
    }
    table get_feature6{
        key={
            hdr.ipv4.ttl : range;
        }
        actions={
            _ttl_last_ass;
        }
        const size = 8;
        const entries={
            0..46 : _ttl_last_ass(0);
            47..157 : _ttl_last_ass(1);
            158..253 : _ttl_last_ass(2);
            254..65535 : _ttl_last_ass(3);
        }
    }

    action p_bits_ass(bit<16> input){
        feature7 = input;
    }
    table get_feature7{
        key={
            hdr.ipv4.total_len : range;
        }
        actions={
            p_bits_ass;
        }
        const size = 8;
        const entries={
            0..56 : p_bits_ass(0);
            57..65535 : p_bits_ass(1);
        }
    }
    
    action get_result_a(bit<16> input){
        detection_result = input;
    }
    
    table get_result{
        key={
            feature1 : ternary;
            feature2 : ternary;
            feature3 : ternary;
            feature4 : ternary;
            feature5 : ternary;
            feature6 : ternary;
            feature7 : ternary;
        }
        actions={
            get_result_a;
            @defaultonly NoAction;
        }
        const size = 256;
        const entries={
            (1, _, _, _, _, 0, _) : get_result_a(5); //一级超速项, A
            (2, _, _, _, _, 0, _) : get_result_a(6); //二级超速项, A
            (1, _, _, _, _, 1, _) : get_result_a(9); //一级超速项, B
            (2, _, _, _, _, 1, _) : get_result_a(10); //二级超速项, B
            (1, _, _, _, _, _, _) : get_result_a(1); //一级超速项
            (2, _, _, _, _, _, _) : get_result_a(2); //二级超速项
            (_, _, _, _, _, 0, _) : get_result_a(4); //异常检测A
            (_, _, _, _, _, 1, _) : get_result_a(8); //异常检测B
            (_, _, _, _, _, _, _) : get_result_a(0); //正常


            // (_, _, _, _, _, 0, _) : get_result_a(0);
            // (0, _, _, _, _, 0, _) : get_result_a(6);
            // (1, _, _, _, 0, 0, 0) : get_result_a(6);
            // (1, _, _, _, 1, 0, 0) : get_result_a(6);
            // (0, _, _, _, _, 0, 1) : get_result_a(6);
            // (2, _, _, _, _, 0, 1) : get_result_a(6);
            // (_, 0, 0, 0, _, 2, _) : get_result_a(2);
            // (_, 1, 0, 0, _, 2, _) : get_result_a(6);
            // (_, _, 2, 0, _, 2, _) : get_result_a(5);
            // (_, 0, 0, 1, _, 2, _) : get_result_a(6);
            // (_, 0, 1, 1, _, 2, _) : get_result_a(6);
            // (_, 2, _, 1, _, 0, _) : get_result_a(0);
            // (_, 2, _, 1, _, 3, _) : get_result_a(1);
        }
    }

    bit<1> temp;




    apply{
        
        
        layer1();
        layer2();
        layer3();


        // Anomaly detection

        get_mean_sq.apply();

        get_std();

        // Desicion Tree Implementation

        get_feature1.apply();
        get_feature2.apply();
        get_feature3.apply();
        get_feature4.apply();
        get_feature5.apply();
        get_feature6.apply();
        get_feature7.apply();

        get_result.apply();

        egress_test_1();
        egress_test_2();
        egress_test_3();
        egress_test_4();
        egress_test_5();
        









    }

}

// --------------------------------------------------------------
//     Egress Deparser
// --------------------------------------------------------------

// control SwitchEgressDeparser(
//         packet_out pkt,
//         inout header_t hdr,
//         in metadata_t eg_md,
//         in egress_intrinsic_metadata_for_deparser_t eg_dprsr_md) {

//     apply {

//         pkt.emit(hdr);
//     }
// }

control SwitchEgressDeparser(
        packet_out pkt,
        inout header_t hdr,
        in metadata_t eg_md,
        in egress_intrinsic_metadata_for_deparser_t eg_dprsr_md) {

    apply {
        pkt.emit(hdr.ethernet);
        pkt.emit(hdr.arp);      
        pkt.emit(hdr.ipv4);     
        pkt.emit(hdr.tcp);      
        pkt.emit(hdr.udp);      
    }
}

Pipeline(SwitchIngressParser(),
         SwitchIngress(),
         SwitchIngressDeparser(),
         SwitchEgressParser(),
         SwitchEgress(),
         SwitchEgressDeparser()) pipe;

Switch(pipe) main;
