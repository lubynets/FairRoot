/*
 * File:   FairTestDetectorDigiLoader.tpl
 * @since 2014-02-08
 * @author: A. Rybalchenko, N. Winckler
 *
 */

template <typename T1, typename T2>
FairTestDetectorDigiLoader<T1, T2>::FairTestDetectorDigiLoader()
    : FairMQSamplerTask("Load class T1")
    , fDigiVector()
    , fHasBoostSerialization(false)
{
    using namespace baseMQ::tools::resolve;
    // coverity[pointless_expression]: suppress coverity warnings on apparant if(const).
    if (is_same<T2, boost::archive::binary_oarchive>::value || is_same<T2, boost::archive::text_oarchive>::value)
    {
        if (has_BoostSerialization<T1, void(T2&, const unsigned int)>::value == 1)
        {
            fHasBoostSerialization = true;
        }
    }
}

template <typename T1, typename T2>
FairTestDetectorDigiLoader<T1, T2>::~FairTestDetectorDigiLoader()
{
    if (fDigiVector.size() > 0)
    {
        fDigiVector.clear();
    }
}

// Default implementation of FairTestDetectorDigiLoader::Exec() with Boost transport data format

template <typename T1, typename T2>
void FairTestDetectorDigiLoader<T1, T2>::Exec(Option_t* opt)
{
    // Default implementation of the base template Exec function using boost
    // the condition check if the input class has a function member with name
    // void serialize(T2 & ar, const unsigned int version) and if the payload are of boost type

    if (fHasBoostSerialization)
    {
        // LOG(INFO) <<" Boost Serialization ok ";

        ostringstream buffer;
        T2 OutputArchive(buffer);
        for (Int_t i = 0; i < fInput->GetEntriesFast(); ++i)
        {
            T1* digi = static_cast<T1*>(fInput->At(i));
            if (!digi)
            {
                continue;
            }
            fDigiVector.push_back(*digi);
        }

        OutputArchive << fDigiVector;
        int size = buffer.str().length();
        fOutput = fTransportFactory->CreateMessage(size);
        memcpy(fOutput->GetData(), buffer.str().c_str(), size);

        // delete the vector content
        if (fDigiVector.size() > 0)
        {
            fDigiVector.clear();
        }
    }
    else
    {
        LOG(ERROR) << " Boost Serialization not ok";
    }
}

// Implementation of FairTestDetectorDigiLoader::Exec() with pure binary transport data format

template <>
void FairTestDetectorDigiLoader<FairTestDetectorDigi, TestDetectorPayload::Digi>::Exec(Option_t* opt)
{
    // // Example of how to send multipart messages (uncomment the code lines to test).
    // // 1. create some data and put it into message (optionaly in one step with zero-copy):
    // string test = "hello";
    // fOutput = fTransportFactory->CreateMessage(test.size());
    // memcpy ((void *) fOutput->GetData(), test.c_str(), test.size());
    // // 2. Send the current message as a part:
    // SendPart();
    // // This will schedule the sending to queueing system.
    // // For the next part, create new message object.
    // // The final part will be sent by the sampler.

    int nDigis = fInput->GetEntriesFast();
    int size = nDigis * sizeof(TestDetectorPayload::Digi);

    fOutput = fTransportFactory->CreateMessage(size);
    TestDetectorPayload::Digi* ptr = static_cast<TestDetectorPayload::Digi*>(fOutput->GetData());

    for (Int_t i = 0; i < nDigis; ++i)
    {
        FairTestDetectorDigi* digi = static_cast<FairTestDetectorDigi*>(fInput->At(i));
        if (!digi)
        {
            continue;
        }
        new (&ptr[i]) TestDetectorPayload::Digi();
        ptr[i] = TestDetectorPayload::Digi();
        ptr[i].fX = digi->GetX();
        ptr[i].fY = digi->GetY();
        ptr[i].fZ = digi->GetZ();
        ptr[i].fTimeStamp = digi->GetTimeStamp();
    }
}

// Implementation of FairTestDetectorDigiLoader::Exec() with Root TMessage transport data format

// helper function to clean up the object holding the data after it is transported.
void free_tmessage (void *data, void *hint)
{
    delete static_cast<TMessage*>(hint);
}

template <>
void FairTestDetectorDigiLoader<FairTestDetectorDigi, TMessage>::Exec(Option_t* opt)
{
    TMessage* message = new TMessage(kMESS_OBJECT);
    message->WriteObject(fInput);
    fOutput = fTransportFactory->CreateMessage(message->Buffer(), message->BufferSize(), free_tmessage, message);
    // note: transport will cleanup the message object when the transfer is done using the provided deallocator (free_tmessage).
}

// Implementation of FairTestDetectorDigiLoader::Exec() with Google Protocol Buffers transport data format

#ifdef PROTOBUF
#include "FairTestDetectorPayload.pb.h"

// helper function to clean up the object holding the data after it is transported.
void free_string (void *data, void *hint)
{
    delete static_cast<string*>(hint);
}

template <>
void FairTestDetectorDigiLoader<FairTestDetectorDigi, TestDetectorProto::DigiPayload>::Exec(Option_t* opt)
{
    int nDigis = fInput->GetEntriesFast();

    TestDetectorProto::DigiPayload dp;

    for (int i = 0; i < nDigis; ++i)
    {
        FairTestDetectorDigi* digi = static_cast<FairTestDetectorDigi*>(fInput->At(i));
        if (!digi)
        {
            continue;
        }
        TestDetectorProto::Digi* d = dp.add_digi();
        d->set_fx(digi->GetX());
        d->set_fy(digi->GetY());
        d->set_fz(digi->GetZ());
        d->set_ftimestamp(digi->GetTimeStamp());
    }

    string* str = new string();
    dp.SerializeToString(str);
    size_t size = str->length();

    fOutput = fTransportFactory->CreateMessage(const_cast<char*>(str->c_str()), size, free_string, str);
    // fOutput = fTransportFactory->CreateMessage(size);
    // memcpy(fOutput->GetData(), str.c_str(), size);
}

#endif /* PROTOBUF */