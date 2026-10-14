#include "WFProtocol.h"
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
using namespace wf;
static int checks = 0;
void check(bool result, const char* name) {
    ++checks;
    if (!result) throw std::runtime_error(name);
}
template <typename F> void mustThrow(F fn, const char* name) {
    bool thrown = false;
    try { fn(); } catch (const std::exception&) { thrown = true; }
    check(thrown, name);
}
bool equal(const Frame& a, const Frame& b) {
    return a.type == b.type && a.sequence == b.sequence && a.payload == b.payload;
}
int main() {
    try {
        // Golden bytes derive from upstream framing, not a claimed live capture.
        check(encode({kData, 0, {0, 0}}) == Bytes({0x3e, 0x0c, 0, 0, 0, 0, 2, 0, 0, 0x0e, 0x3c}), "init framing golden");
        check(encode({kAck, 1, {}}) == Bytes({0x3e, 1, 1, 0, 0, 0, 0, 2, 0x3c}), "ACK framing golden");
        Frame original{kData, 1, {0x3c, 0x3d, 0x3e, 0, 0xff}};
        auto wire = encode(original);
        for (size_t split = 0; split <= wire.size(); ++split) {
            StreamDecoder decoder;
            auto frames = decoder.feed(Bytes(wire.begin(), wire.begin() + split));
            auto rest = decoder.feed(Bytes(wire.begin() + split, wire.end()));
            frames.insert(frames.end(), rest.begin(), rest.end());
            check(frames.size() == 1 && equal(frames[0], original), "split escaping round trip");
        }
        StreamDecoder bytewise;
        size_t received = 0;
        for (auto byte : wire) for (const auto& frame : bytewise.feed({byte})) { check(equal(frame, original), "bytewise payload"); ++received; }
        check(received == 1, "bytewise one frame");
        Bytes joined{0, 0xff, 0x3c}; joined.insert(joined.end(), wire.begin(), wire.end());
        auto ackWire = encode({kAck, 0, {}}); joined.insert(joined.end(), ackWire.begin(), ackWire.end());
        StreamDecoder jointDecoder;
        auto frames = jointDecoder.feed(joined);
        check(frames.size() == 2 && equal(frames[0], original) && frames[1].type == kAck, "joined and leading junk");
        Bytes bad = encode({kData, 0, {0x22, 0}}); bad[7] ^= 1;
        bad.insert(bad.end(), wire.begin(), wire.end());
        StreamDecoder resync;
        frames = resync.feed(bad);
        check(frames.size() == 1 && equal(frames[0], original) && resync.rejectedFrames() == 1, "checksum reject resync");
        Bytes invalidEscape{0x3e, 0x3d, 0x11}; invalidEscape.insert(invalidEscape.end(), wire.begin(), wire.end());
        check(resync.feed(invalidEscape).size() == 1, "invalid escape resync");
        Bytes dangling{0x3e, 0x3d, 0x3c}; dangling.insert(dangling.end(), wire.begin(), wire.end());
        check(resync.feed(dangling).size() == 1, "dangling escape resync");
        Bytes nested{0x3e, 0x0c, 0}; nested.insert(nested.end(), wire.begin(), wire.end());
        check(resync.feed(nested).size() == 1, "nested start resync");
        Bytes excessive{0x3e, 0x0c, 0, 0xff, 0xff, 0xff, 0xff};
        excessive.insert(excessive.end(), wire.begin(), wire.end());
        check(resync.feed(excessive).size() == 1, "declared length bounded resync");
        Bytes extra{0x3e, 1, 0, 0, 0, 0, 0, 1, 0, 0x3c};
        check(resync.feed(extra).empty(), "reject surplus unescaped byte");
        mustThrow([] { encode({kData, 0, Bytes(4097, 0)}); }, "encode bounds");
        StreamDecoder small(2);
        check(small.feed(wire).empty() && small.rejectedFrames() == 1, "decoder bounds");
        resync.reset(); check(resync.rejectedFrames() == 0, "reset counters and buffer");
        Bytes allBytes;
        for (int i = 0; i < 256; ++i) allBytes.push_back(uint8_t(i));
        Frame exhaustive{kData, 0, allBytes};
        StreamDecoder exhaustiveDecoder;
        frames = exhaustiveDecoder.feed(encode(exhaustive));
        check(frames.size() == 1 && equal(frames[0], exhaustive), "all byte values round trip");
        uint32_t randomState = 0x57464354;
        StreamDecoder fuzz;
        for (int trial = 0; trial < 256; ++trial) {
            Bytes noisy;
            for (int i = 0; i < 256; ++i) {
                randomState ^= randomState << 13; randomState ^= randomState >> 17; randomState ^= randomState << 5;
                noisy.push_back(uint8_t(randomState));
            }
            noisy.insert(noisy.end(), wire.begin(), wire.end());
            frames = fuzz.feed(noisy);
            check(!frames.empty() && equal(frames.back(), original), "seeded corruption always resynchronizes");
        }

        BatteryState battery;
        check(parseBattery({0x23, 0x01, 0, 0, 100, 1}, 1, BatteryLayout::LeftRight, battery), "dual battery structural parse");
        check(battery.left->level == 0 && !battery.left->charging && battery.right->level == 100 && battery.right->charging, "separate LR and charging");
        check(parseBattery({0x25, 0x01, 0xff, 0, 62, 0}, 1, BatteryLayout::LeftRight, battery) && !battery.left && battery.right->level == 62, "unavailable earbud");
        check(parseBattery({0x23, 2, 0xff, 0}, 2, BatteryLayout::Case, battery) && !battery.caseBattery, "unavailable case");
        check(parseBattery({0x23, 2, 30, 1}, 2, BatteryLayout::Case, battery) && battery.caseBattery->charging, "case charging");
        check(!parseBattery({0x23, 1, 42, 0, 101, 0}, 1, BatteryLayout::LeftRight, battery) && battery.right->level == 62 && !battery.left, "invalid battery atomic update");
        check(!parseBattery({0x23, 9, 30, 0}, 2, BatteryLayout::Case, battery), "reject unknown subtype");
        check(parseBattery({0x23, 2, 30, 2}, 2, BatteryLayout::Case, battery) && !battery.caseBattery->chargingKnown && !battery.caseBattery->charging, "unknown charging retained");
        check(parseBattery({0x23, 2, 100, 3}, 2, BatteryLayout::Case, battery) && battery.caseBattery->fullyCharged && !battery.caseBattery->charging, "charged retained");
        check(parseBattery({0x23, 2, 30, 0xff}, 2, BatteryLayout::Case, battery) && battery.caseBattery->level == 30 && !battery.caseBattery->chargingKnown, "out of range charging does not hide percent");
        check(!parseBattery({0x23, 2, 30, 4}, 2, BatteryLayout::Case, battery), "invalid charging");
        check(!parseBattery({0x23, 2, 30}, 2, BatteryLayout::Case, battery), "truncated battery");

        auto ambient = parseAmbient({0x67, 0x17, 1, 1, 0, 0, 1});
        check(ambient && ambient->mode == AmbientMode::NoiseCancelling, "ANC parse");
        ambient = parseAmbient({0x69, 0x17, 1, 1, 1, 1, 20});
        check(ambient && ambient->mode == AmbientMode::Ambient && ambient->focusOnVoice && ambient->level == 20, "ambient notification parse");
        ambient = parseAmbient({0x67, 0x17, 1, 0, 0, 0, 1});
        check(ambient && ambient->mode == AmbientMode::Off, "off parse");
        check(!parseAmbient({0x67, 2, 1, 1, 0, 0, 1}), "unverified ANC subtype rejected");
        check(setAmbient({AmbientMode::Ambient, true, 20}) == Bytes({0x68, 0x17, 1, 1, 1, 1, 20}), "ambient encode");
        mustThrow([] { setAmbient({AmbientMode::Ambient, false, 256}); }, "ambient bounds");
        auto ambientCapability = parseAmbientCapabilities({0x61, 0x17, 2, 0, 1, 20, 1, 1, 1, 20, 1});
        check(ambientCapability && ambientCapability->ranges.size() == 2
              && ambientCapability->ranges[0].mode == 0 && ambientCapability->ranges[0].maximum == 20
              && ambientCapability->ranges[1].mode == 1 && ambientCapability->ranges[1].minimum == 1, "live ANC capability fixture");
        check(!parseAmbientCapabilities({0x61, 0x17, 2, 0, 1, 20, 1}), "truncated ambient range rejected");
        check(!parseAmbientCapabilities({0x61, 0x17, 1, 0, 20, 1, 1}), "inverted ambient range rejected");
        check(!parseAmbientCapabilities({0x61, 0x17, 1, 0, 1, 20, 0}), "zero ambient step rejected");
        check(!parseAmbientCapabilities({0x61, 0x17, 2, 0, 1, 20, 1, 0, 1, 20, 1}), "duplicate ambient mode rejected");

        auto autoAmbient=parseAmbient({0x67,0x15,1,0,0,2,1,16});
        check(autoAmbient && autoAmbient->mode==AmbientMode::Off && autoAmbient->ncValue==2
              && autoAmbient->inquiry==0x15 && autoAmbient->focusOnVoice && autoAmbient->level==16, "live WF Auto NC baseline");
        autoAmbient->mode=AmbientMode::NoiseCancelling;
        check(setAmbient(*autoAmbient)==Bytes({0x68,0x15,1,1,0,2,1,16}), "Auto NC preserves returned NC value");
        check(parseAmbient({0x69,0x15,1,1,1,2,1,16})->mode==AmbientMode::Ambient, "live Auto NC ambient notification");
        check(!parseAmbient({0x67,0x15,1,1,0,6,1,16}), "Auto NC invalid NC value");
        check(!parseAmbient({0x67,0x15,1,1,0,2,1}), "Auto NC truncated rejected");
        check(parseAmbientCapabilities({0x61,0x15,2,0,1,20,1,1,1,20,1}).has_value(), "live Auto NC capability");
        auto eq = parseEQ({0x57, 0, 0xa0, 6, 0, 5, 10, 15, 20, 10});
        check(eq && eq->clearBass == -10 && (*eq->bands)[0] == -5 && (*eq->bands)[3] == 10, "EQ bias decode");
        eq = parseEQ({0x57, 0, 0x10, 0});
        check(eq && eq->preset == 0x10 && !eq->bands && !eq->clearBass, "EQ preset no band data");
        check(!parseEQ({0x57, 0, 0xa0, 6, 0, 5, 10, 15, 21, 10}), "EQ invalid gain");
        check(!parseEQ({0x57, 0, 0xa0, 6, 10}), "EQ truncated count");
        check(setEQCustom(0, {-10, -5, 0, 5, 10}) == Bytes({0x58, 0, 0xa0, 6, 10, 0, 5, 10, 15, 20}), "EQ encode");
        mustThrow([] { setEQCustom(11, {0, 0, 0, 0, 0}); }, "EQ bounds reject");
        // Actual hardware replies captured by root read probe on this Mac:
        // WF-1000XM4, firmware 2.3.1. No writes needed to establish these.
        check(parseBattery({0x23, 1, 0x64, 0, 0x64, 0}, 1, BatteryLayout::LeftRight, battery)
              && battery.left->level == 100 && battery.right->level == 100, "live left right fixture");
        check(parseBattery({0x23, 2, 0x5d, 0}, 2, BatteryLayout::Case, battery)
              && battery.caseBattery->level == 93, "live case fixture");
        eq = parseEQ({0x57, 0, 0x11, 6, 0x12, 9, 0x0b, 0x0a, 0x0d, 0x0f});
        check(eq && eq->preset == 0x11 && eq->clearBass == 8 && *eq->bands == std::array<int, 5>{-1, 1, 0, 3, 5}, "live EQ fixture");
        Bytes eqCapability{0x51, 0, 6, 21, 12, 0, 0, 0x10, 0, 0x11, 0, 0x12, 0, 0x13, 0, 0x14, 0, 0x15, 0, 0x16, 0, 0x17, 0, 0xa0, 0, 0xa1, 0, 0xa2, 0};
        auto capability = parseEQCapabilities(eqCapability);
        check(capability && capability->supportsEditor() && capability->presets.size() == 12
              && capability->presets[11].id == 0xa2, "live EQ capability fixture");
        auto truncatedCapability = eqCapability; truncatedCapability.pop_back();
        check(!parseEQCapabilities(truncatedCapability), "truncated EQ capabilities rejected");
        auto extraCapability = eqCapability; extraCapability.push_back(0);
        check(!parseEQCapabilities(extraCapability), "surplus EQ capability bytes rejected");
        check(!parseEQCapabilities({0x51, 0, 6, 21, 1, 0, 9, 'x'}), "invalid preset name length rejected");
        check(!parseEQCapabilities({0x51, 0, 6, 21, 2, 0, 0, 0, 0}), "duplicate preset ids rejected");
        capability = parseEQCapabilities({0x51, 0, 6, 21, 1, 0xa0, 3, 'E', 'Q', '!'});
        check(capability && capability->presets[0].name == "EQ!", "length-prefixed name decoded");
        capability = parseEQCapabilities({0x51, 0, 5, 21, 1, 0, 0});
        check(capability && !capability->supportsEditor(), "different band count cannot enable editor");

        auto protocolInfo=parseProtocolInfo({1,0,3,0,0,4,0,0},ProtocolFamily::V2);
        check(protocolInfo && protocolInfo->table1 && protocolInfo->table2 && protocolInfo->version==0x03000004,"live v2 handshake enabled zero flags");
        protocolInfo=parseProtocolInfo({1,0,3,0,0,4,0,1},ProtocolFamily::V2);
        check(protocolInfo && protocolInfo->table1 && !protocolInfo->table2,"table2 disabled one flag");
        protocolInfo=parseProtocolInfo({1,0,3,0,0,4,1,0},ProtocolFamily::V2);
        check(protocolInfo && !protocolInfo->table1 && protocolInfo->table2,"table1 disabled one flag");
        check(!parseProtocolInfo({1,0,3,0,0,4,0,2},ProtocolFamily::V2),"invalid handshake flag rejected");
        check(!parseProtocolInfo({1,0,0,1},ProtocolFamily::V2),"v1 handshake rejected on v2 service");
        protocolInfo=parseProtocolInfo({1,0,0,1},ProtocolFamily::V1);
        check(protocolInfo && protocolInfo->version==1 && !protocolInfo->table2,"legacy handshake isolated");
        auto supportV2=parseSupportFunctions({7,0,2,0xe1,0,0xf1,1},ProtocolFamily::V2);
        check(supportV2 && *supportV2==std::vector<uint8_t>{0xe1,0xf1},"v2 function records exclude version bytes");
        auto supportV1=parseSupportFunctions({7,0,2,0xe1,0xf3},ProtocolFamily::V1);
        check(supportV1 && supportV1->size()==2,"v1 function byte list");
        check(!parseSupportFunctions({7,0,2,0xe1,0xf3},ProtocolFamily::V2),"never treat v1 support as v2");
        auto specs=settingSpecs(ProtocolFamily::V2,{0xe1,0xe2,0xf1,0xf2,0x25});
        check(specs.size()==8,"capability-bound setting inventory");
        for(auto& spec:specs) {
            Bytes state(spec.responseSize,0); state[0]=spec.reply;state[1]=spec.inquiry;
            state[spec.valueOffset]=spec.inverted?1:spec.options.front().value;
            if(spec.id=="autoOff") {spec.options={{0x10,"Removed"},{0x11,"Never"}};state[2]=0x10;}
            auto before=settingValue(spec,state);
            check(before.has_value(),"typed setting read");
            auto command=settingCommand(spec,state,spec.options.back().value);
            check(command[0]==spec.set && command[1]==spec.inquiry,"typed setting write profile");
            auto response=command;response[0]=spec.reply;
            check(settingValue(spec,response)==spec.options.back().value,"typed setting roundtrip");
            auto malformed=state;malformed.pop_back();check(!settingValue(spec,malformed),"typed setting truncation");
            mustThrow([&]{settingCommand(spec,state,999);},"reject unadvertised setting value");
        }
        auto legacySpecs=settingSpecs(ProtocolFamily::V1,{0xe1,0xe2,0xf3});
        check(legacySpecs.size()==3 && legacySpecs[0].inquiry==1 && legacySpecs[1].inquiry==2 && legacySpecs[2].inquiry==3,"legacy selectors isolated");
        auto legacyCapability=parseLegacyAmbientCapabilities({0x61,2,2,2,1,2,0,20,1,10});
        check(legacyCapability && legacyCapability->ranges.size()==2 && legacyCapability->ranges[0].maximum==20 && legacyCapability->ranges[1].maximum==10,"legacy exact capability ranges");
        legacyCapability=parseLegacyAmbientCapabilities({0x61,2,1,2,1,1,0,12});
        check(legacyCapability && legacyCapability->ranges[0].maximum==12,"legacy range derived from actual record");
        check(!parseLegacyAmbientCapabilities({0x61,2,2}),"legacy header alone cannot enable controls");
        check(!parseLegacyAmbientCapabilities({0x61,2,2,2,1,2,0,20}),"legacy truncated record list rejected");
        check(!parseLegacyAmbientCapabilities({0x61,2,2,2,1,2,0,20,0,20}),"legacy duplicate modes rejected");
        check(!parseLegacyAmbientCapabilities({0x61,2,2,2,0,1,0,20}),"legacy onoff capability cannot enable level editor");
        check(!parseLegacyAmbientCapabilities({0x61,2,2,2,1,1,1,20}),"legacy missing normal mode rejected");
        check(!parseLegacyAmbientCapabilities({0x61,2,2,2,1,1,0,0}),"legacy zero range rejected");
        check(!parseLegacyAmbientCapabilities({0x61,2,2,2,1,1,0,21}),"legacy unsupported range cannot enable writer");
        check(!parseLegacyAmbientCapabilities({0x61,2,3,2,1,1,0,20}),"legacy invalid NC schema rejected");
        auto legacyANC=parseLegacyAmbient({0x67,2,1,1,2,1,0,0});
        check(legacyANC && legacyANC->mode==AmbientMode::NoiseCancelling && legacyANC->inquiry==2,"legacy ANC decode");
        check(legacyANC && setAmbient(*legacyANC)==Bytes({0x68,2,0x11,1,2,1,0,0}),"legacy ANC encode");
        auto assignment=parseAssignmentCapabilities({0xf1,3,1,0,0,0,2,0,1,0,0,2,0xff,1,0,0,0});
        check(assignment && assignment->size()==1 && (*assignment)[0].presets==std::vector<uint8_t>{0,0xff},"typed assignment nested capability");
        check(!parseAssignmentCapabilities({0xf1,3,1,0,0,0,2,0,1,0,0}),"truncated assignment capability");
        auto history=parsePairedDevices({0x37,0,1,'a','c',':','8','0',':','0','a',':','7','e',':','4','9',':','7','2',1,3,'M','a','c',0});
        check(history && history->size()==1 && (*history)[0].name=="Mac" && (*history)[0].status==1,"paired history typed parse");
        check(!parsePairedDevices({0x37,0,1,0}),"paired history truncated");

        CommandTracker tracker;
        auto tx = tracker.begin({0x22, 1}, 0x23, 1, 100, 1000);
        check(tx.sequence == 0 && tracker.status() == TransactionStatus::Waiting, "initial sequence");
        mustThrow([&] { tracker.begin({0, 0}, 1, {}, 100, 1000); }, "one command in flight");
        check(!tracker.observe({kAck, 0, {}}), "stale wrong ACK ignored");
        check(tracker.observe({kAck, 1, {}}) && tracker.acknowledged() && tracker.status() == TransactionStatus::Waiting, "ACK alone not GET complete");
        check(!tracker.observe({kAck, 1, {}}), "duplicate ACK ignored");
        check(!tracker.observe({kData, 0, {0x23, 2, 30, 0}}), "unrelated notification ignored");
        check(tracker.observe({kData, 0, {0x23, 1, 30, 0, 42, 0}}) && tracker.status() == TransactionStatus::Complete, "matching RET completes GET");
        tx = tracker.begin({0x66, 0x17}, 0x67, 0x17, 200, 1000);
        check(tx.sequence == 1, "sequence toggles ACK");
        check(tracker.observe({kData, 1, {0x67, 0x17, 1, 0, 0, 0, 1}}) && tracker.status() == TransactionStatus::Waiting, "response before ACK retained");
        check(tracker.observe({kAck, 0, {}}) && tracker.status() == TransactionStatus::Complete, "ACK after response complete");
        tracker.begin({0x58, 0, 0, 0}, {}, {}, 200, 1000);
        check(!tracker.expire(1199) && tracker.expire(1200) && tracker.status() == TransactionStatus::TimedOut, "timeout boundary");
        check(!tracker.observe({kAck, 1, {}}) && !tracker.expire(1300), "late ACK does not revive timed out command");
        tracker.reset(); tx = tracker.begin({0x58, 0, 0, 0}, {}, {}, 0, 100);
        check(tx.sequence == 0 && tracker.observe({kAck, 1, {}}) && tracker.status() == TransactionStatus::Complete, "reconnect resets and SET ACK completion");
        tracker.reset();
        auto table2=tracker.begin({0x46,1},0x47,1,0,100,0x0e);
        check(table2.type==0x0e,"table2 frame type");
        check(!tracker.observe({kData,0,{0x47,1,0,1}}),"table1 cannot satisfy table2 request");
        check(tracker.observe({0x0e,0,{0x47,1,0,1}}),"table2 reply matched");
        check(tracker.observe({kAck,1,{}}) && tracker.status()==TransactionStatus::Complete,"table2 ACK completes");
        ReceiveWindow receive;
        auto rx = receive.observe({kData, 0, {0x23, 1, 42, 0, 42, 0}});
        check(rx.deliver && rx.ack && rx.ack->sequence == 1, "received DATA ACK toggle");
        rx = receive.observe({kData, 0, {0x23, 1, 42, 0, 42, 0}});
        check(!rx.deliver && rx.ack && rx.ack->sequence == 1, "duplicate DATA reACK without redelivery");
        rx = receive.observe({kData, 1, {0x23, 1, 42, 0, 42, 0}});
        check(rx.deliver && rx.ack->sequence == 0, "new sequence deliver");
        check(!receive.observe({kAck, 0, {}}).ack, "never ACK ACK");
        receive.reset(); check(receive.observe({kData, 1, {0x23, 1, 42, 0, 42, 0}}).deliver, "receive reset");
        std::cout << checks << " protocol checks passed\n";
        return EXIT_SUCCESS;
    } catch (const std::exception& error) {
        std::cerr << "Protocol test failed after " << checks << " checks: " << error.what() << '\n';
        return EXIT_FAILURE;
    }
}
