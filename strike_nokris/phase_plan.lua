-- Build86657 reconstructed normal-solo roster, pinned by E030 phase_plan.py.
-- Exact SDK slots/counts/rule joins are static facts; encounter timing is policy.
-- Native phase inputs, immunity and result adapters are separate requirements.
local phases={
    {
        crystals={38,45},
        crystal_symbols={"PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_1_OB_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_CRYSTAL_NAMED","PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_2_OB_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_CRYSTAL_NAMED"},
        carriers={
            {slot=40,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_1_SQ_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_BALL_KNIGHT",counts={1},rule=278,rule_symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_1_SR_NOKRIS_MAJOR_SHIELD_RELIC_KNIGHT"},
            {slot=47,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_2_SQ_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_BALL_KNIGHT",counts={1},rule=306,rule_symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_2_SR_NOKRIS_MAJOR_SHIELD_RELIC_KNIGHT"},
        },
        supports={
            {slot=91,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_3_SQ_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_THRALL_AND_TROOPER",counts={1,0}},
            {slot=103,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_6_SQ_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_THRALL_AND_TROOPER",counts={1,0}},
            {slot=107,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_7_SQ_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_THRALL_AND_TROOPER",counts={1,0}},
            {slot=111,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_8_SQ_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_THRALL_AND_TROOPER",counts={1,0}},
            {slot=119,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_10_SQ_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_THRALL_AND_TROOPER",counts={0,1}},
            {slot=127,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_12_SQ_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_THRALL_AND_TROOPER",counts={0,1}},
        },
    },
    {
        crystals={52,59},
        crystal_symbols={"PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_3_OB_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_CRYSTAL_NAMED","PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_4_OB_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_CRYSTAL_NAMED"},
        carriers={
            {slot=54,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_3_SQ_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_BALL_KNIGHT",counts={1},rule=322,rule_symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_3_SR_NOKRIS_MAJOR_SHIELD_RELIC_KNIGHT"},
            {slot=61,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_4_SQ_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_BALL_KNIGHT",counts={1},rule=342,rule_symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_4_SR_NOKRIS_MAJOR_SHIELD_RELIC_KNIGHT"},
        },
        supports={
            {slot=79,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_0_SQ_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_THRALL_AND_TROOPER",counts={1,0}},
            {slot=83,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_1_SQ_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_THRALL_AND_TROOPER",counts={1,0}},
            {slot=87,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_2_SQ_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_THRALL_AND_TROOPER",counts={0,1}},
            {slot=95,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_4_SQ_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_THRALL_AND_TROOPER",counts={0,1}},
            {slot=32,symbol="SQ_WIZARD_G_1",counts={1}},
            -- Retail shows two Wizard majors together in the second protected interval (video 18:46).
            {slot=33,symbol="SQ_WIZARD_G_2",counts={1}},
        },
    },
    {
        crystals={66,73},
        crystal_symbols={"PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_5_OB_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_CRYSTAL_NAMED","PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_6_OB_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_CRYSTAL_NAMED"},
        carriers={
            {slot=68,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_5_SQ_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_BALL_KNIGHT",counts={1},rule=354,rule_symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_5_SR_NOKRIS_MAJOR_SHIELD_RELIC_KNIGHT"},
            {slot=75,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_6_SQ_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_BALL_KNIGHT",counts={1},rule=163,rule_symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_SHIELD_6_SR_NOKRIS_MAJOR_SHIELD_RELIC_KNIGHT"},
        },
        supports={
            {slot=99,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_5_SQ_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_THRALL_AND_TROOPER",counts={1,1}},
            {slot=115,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_9_SQ_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_THRALL_AND_TROOPER",counts={1,1}},
            {slot=131,symbol="PF_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_13_SQ_EXP_ULTRA_WIZARD_NOKRIS_ICE_GEYSER_THRALL_AND_TROOPER",counts={1,1}},
        },
    },
}
-- Portal-side pairs precede the central pair. Move each crystal with its authored carrier/rule;
-- support waves and native health-phase ordinals retain their chronological order.
phases[1].crystals,phases[2].crystals=phases[2].crystals,phases[1].crystals
phases[1].crystal_symbols,phases[2].crystal_symbols=phases[2].crystal_symbols,phases[1].crystal_symbols
phases[1].carriers,phases[2].carriers=phases[2].carriers,phases[1].carriers
return phases
