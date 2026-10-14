#include "WFProtocol.h"
#include <random>
#include <iostream>
#include <stdexcept>
using namespace wf;
static void require(bool value) { if(!value) throw std::runtime_error("Security regression failed"); }
int main() {
    SettingSpec empty{};
    require(!settingValue(empty,{}));
    SettingSpec shortSpeak{"speakToChat","","",0,0,0,1,2,3,2,{{0,"Off"}},false,false};
    bool threw=false;
    try { settingCommand(shortSpeak,{1,0,0},0); } catch(const std::invalid_argument&) { threw=true; }
    require(threw);
    require(!parseGeneralCapability({0xd1,0xd2,0,2,0,0})); // invalid string format
    require(parseGeneralCapability({0xd1,0xd2,0,0,0,0}).has_value());
    require(parseGeneralCapability({0xd1,0xd2,0,1,0,0}).has_value()); // enum string format is valid
    auto general=*parseGeneralCapability({0xd1,0xd2,0,1,0,0});
    require(settingValue(general,{0xd7,0xd2,0,0})==1);
    require(!settingValue(general,{0xd7,0xd2,1,0})); // capability / parameter type mismatch
    std::mt19937 random(0x534f4e59);
    StreamDecoder decoder;
    const Bytes seeds[]={ {0x67,0x15,1,0,0,2,1,16}, {0x23,1,100,0,92,0},
        {0x57,0,0x11,6,18,9,11,10,13,15}, {0xf1,3,1,0,0,0,1,0,0,0},
        {0xd1,0xd2,0,0,1,'A',0}, {0x37,0,0,0xff} };
    for(unsigned iteration=0;iteration<100000;++iteration) {
        Bytes payload;
        if(iteration%2) { payload=seeds[iteration%6];
            if(!payload.empty()) payload[random()%payload.size()]=uint8_t(random());
            if(iteration%3==0) payload.resize(random()%(payload.size()+1));
        } else { payload.resize(random()%513); for(auto& byte:payload) byte=uint8_t(random()); }
        BatteryState state;
        parseBattery(payload,0,BatteryLayout::Single,state);
        parseBattery(payload,1,BatteryLayout::LeftRight,state);
        parseBattery(payload,2,BatteryLayout::Case,state);
        parseAmbient(payload); parseAmbientCapabilities(payload); parseLegacyAmbient(payload);
        parseLegacyAmbientCapabilities(payload); parseEQ(payload); parseEQCapabilities(payload);
        parseProtocolInfo(payload,ProtocolFamily::V1); parseProtocolInfo(payload,ProtocolFamily::V2);
        parseSupportFunctions(payload,ProtocolFamily::V1); parseSupportFunctions(payload,ProtocolFamily::V2);
        parseGeneralCapability(payload); parsePairedDevices(payload); parseAssignmentCapabilities(payload);
        auto frames=decoder.feed(payload);
        for(const auto& frame:frames) require(frame.payload.size()<=kMaxPayload);
        if(iteration%100==0) decoder.reset();
    }
    decoder.reset();
    decoder.feed(Bytes(65536,0x3e));
    auto valid=decoder.feed(encode({kData,0,{0,0}}));
    require(valid.size()==1 && valid[0].payload==Bytes({0,0}));
    std::cout << "100000 deterministic malformed-input cases and security regressions passed\n";
}
