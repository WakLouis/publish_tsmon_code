#include <core.p4>
#if __TARGET_TOFINO__ == 2
#include <t2na.p4>
#else
#include <tna.p4>
#endif

#include "./headers.p4"
#include "./util.p4"

struct metadata_t{

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


    action dmac_action(bit<9> port){
        ig_tm_md.ucast_egress_port = port;
    }

    table dmac{
        key={
            ig_intr_md.ingress_port : exact;
        }
        actions={
            dmac_action;
        }
        const size = 4;
        const entries={
            176 : dmac_action(184);
            184 : dmac_action(176);
        }
    }


    apply{
        dmac.apply();

        ig_tm_md.bypass_egress = 1w1;


        
        

        

        

    }
}

// --------------------------------------------------------------
//     Ingress Parser
// --------------------------------------------------------------


parser SwitchIngressParser(
        packet_in pkt,
        out header_t hdr,
        out metadata_t ig_md,
        out ingress_intrinsic_metadata_t ig_intr_md) {

    state start {
        pkt.extract(ig_intr_md);
        transition parse_ethernet;
    }


    state parse_ethernet {
        pkt.advance(PORT_METADATA_SIZE);
        pkt.extract(hdr.ethernet);
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


    apply {
        
        pkt.emit(hdr);
    }
}



Pipeline(SwitchIngressParser(),
         SwitchIngress(),
         SwitchIngressDeparser(),
         EmptyEgressParser(),
         EmptyEgress(),
         EmptyEgressDeparser()) pipe;

Switch(pipe) main;
