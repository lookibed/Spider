options gen2

typedef size_t = uint64
typedef int32_t = int
typedef int64_t = int64
typedef uint8_t = uint8
typedef uint32_t = uint
typedef uint64_t = uint64
typedef intptr_t = int64
typedef u8 = uint8
typedef i16 = int
typedef u32 = uint
typedef i32 = int
struct strmData_t {
    pStrmBuffStart : uint8?
    pStrmCurrPos : uint8?
    bitPosInWord : uint
    strmBuffSize : uint
    strmBuffReadBits : uint
}
struct hrdParameters_t {
    cpbCnt : uint
    bitRateScale : uint
    cpbSizeScale : uint
    bitRateValue : array<uint>
    cpbSizeValue : array<uint>
    cbrFlag : array<uint>
    initialCpbRemovalDelayLength : uint
    cpbRemovalDelayLength : uint
    dpbOutputDelayLength : uint
    timeOffsetLength : uint
}
struct vuiParameters_t {
    aspectRatioPresentFlag : uint
    aspectRatioIdc : uint
    sarWidth : uint
    sarHeight : uint
    overscanInfoPresentFlag : uint
    overscanAppropriateFlag : uint
    videoSignalTypePresentFlag : uint
    videoFormat : uint
    videoFullRangeFlag : uint
    colourDescriptionPresentFlag : uint
    colourPrimaries : uint
    transferCharacteristics : uint
    matrixCoefficients : uint
    chromaLocInfoPresentFlag : uint
    chromaSampleLocTypeTopField : uint
    chromaSampleLocTypeBottomField : uint
    timingInfoPresentFlag : uint
    numUnitsInTick : uint
    timeScale : uint
    fixedFrameRateFlag : uint
    nalHrdParametersPresentFlag : uint
    nalHrdParameters : hrdParameters_t
    vclHrdParametersPresentFlag : uint
    vclHrdParameters : hrdParameters_t
    lowDelayHrdFlag : uint
    picStructPresentFlag : uint
    bitstreamRestrictionFlag : uint
    motionVectorsOverPicBoundariesFlag : uint
    maxBytesPerPicDenom : uint
    maxBitsPerMbDenom : uint
    log2MaxMvLengthHorizontal : uint
    log2MaxMvLengthVertical : uint
    numReorderFrames : uint
    maxDecFrameBuffering : uint
}
struct seqParamSet_t {
    profileIdc : uint
    levelIdc : uint
    seqParameterSetId : uint
    maxFrameNum : uint
    picOrderCntType : uint
    maxPicOrderCntLsb : uint
    deltaPicOrderAlwaysZeroFlag : uint
    offsetForNonRefPic : int
    offsetForTopToBottomField : int
    numRefFramesInPicOrderCntCycle : uint
    offsetForRefFrame : int?
    numRefFrames : uint
    gapsInFrameNumValueAllowedFlag : uint
    picWidthInMbs : uint
    picHeightInMbs : uint
    frameCroppingFlag : uint
    frameCropLeftOffset : uint
    frameCropRightOffset : uint
    frameCropTopOffset : uint
    frameCropBottomOffset : uint
    vuiParametersPresentFlag : uint
    vuiParameters : vuiParameters_t?
    maxDpbSize : uint
}
struct picParamSet_t {
    picParameterSetId : uint
    seqParameterSetId : uint
    picOrderPresentFlag : uint
    numSliceGroups : uint
    sliceGroupMapType : uint
    runLength : uint?
    topLeft : uint?
    bottomRight : uint?
    sliceGroupChangeDirectionFlag : uint
    sliceGroupChangeRate : uint
    picSizeInMapUnits : uint
    sliceGroupId : uint?
    numRefIdxL0Active : uint
    picInitQp : uint
    chromaQpIndexOffset : int
    deblockingFilterControlPresentFlag : uint
    constrainedIntraPredFlag : uint
    redundantPicCntPresentFlag : uint
}
struct image_t {
    data : uint8?
    width : uint
    height : uint
    luma : uint8?
    cb : uint8?
    cr : uint8?
}
enum nalUnitType_e {
    NAL_CODED_SLICE = 1
    NAL_CODED_SLICE_IDR = 5
    NAL_SEI = 6
    NAL_SEQ_PARAM_SET = 7
    NAL_PIC_PARAM_SET = 8
    NAL_ACCESS_UNIT_DELIMITER = 9
    NAL_END_OF_SEQUENCE = 10
    NAL_END_OF_STREAM = 11
    NAL_FILLER_DATA = 12
    NAL_MAX_TYPE_VALUE = 31
}
struct nalUnit_t {
    nalUnitType : nalUnitType_e
    nalRefIdc : uint
}
struct refPicListReorderingOperation_t {
    reorderingOfPicNumsIdc : uint
    absDiffPicNum : uint
    longTermPicNum : uint
}
struct refPicListReordering_t {
    refPicListReorderingFlagL0 : uint
    command : array<refPicListReorderingOperation_t>
}
struct memoryManagementOperation_t {
    memoryManagementControlOperation : uint
    differenceOfPicNums : uint
    longTermPicNum : uint
    longTermFrameIdx : uint
    maxLongTermFrameIdx : uint
}
struct decRefPicMarking_t {
    noOutputOfPriorPicsFlag : uint
    longTermReferenceFlag : uint
    adaptiveRefPicMarkingModeFlag : uint
    operation : array<memoryManagementOperation_t>
}
struct sliceHeader_t {
    firstMbInSlice : uint
    sliceType : uint
    picParameterSetId : uint
    frameNum : uint
    idrPicId : uint
    picOrderCntLsb : uint
    deltaPicOrderCntBottom : int
    deltaPicOrderCnt : array<int>
    redundantPicCnt : uint
    numRefIdxActiveOverrideFlag : uint
    numRefIdxL0Active : uint
    sliceQpDelta : int
    disableDeblockingFilterIdc : uint
    sliceAlphaC0Offset : int
    sliceBetaOffset : int
    sliceGroupChangeCycle : uint
    refPicListReordering : refPicListReordering_t
    decRefPicMarking : decRefPicMarking_t
}
enum dpbPictureStatus_e {
    UNUSED = 0
    NON_EXISTING = 1
    SHORT_TERM = 2
    LONG_TERM = 3
}
struct dpbPicture_t {
    data : uint8?
    pAllocatedData : uint8?
    picNum : int
    frameNum : uint
    picOrderCnt : int
    status : dpbPictureStatus_e
    toBeDisplayed : uint
    picId : uint
    numErrMbs : uint
    isIdr : uint
}
struct dpbOutPicture_t {
    data : uint8?
    picId : uint
    numErrMbs : uint
    isIdr : uint
}
struct dpbStorage_t {
    buffer : dpbPicture_t?
    list : dpbPicture_t??
    currentOut : dpbPicture_t?
    outBuf : dpbOutPicture_t?
    numOut : uint
    outIndex : uint
    maxRefFrames : uint
    dpbSize : uint
    maxFrameNum : uint
    maxLongTermFrameIdx : uint
    numRefFrames : uint
    fullness : uint
    prevRefFrameNum : uint
    lastContainsMmco5 : uint
    noReordering : uint
    flushed : uint
}
enum mbType_e {
    P_Skip = 0
    P_L0_16x16 = 1
    P_L0_L0_16x8 = 2
    P_L0_L0_8x16 = 3
    P_8x8 = 4
    P_8x8ref0 = 5
    I_4x4 = 6
    I_16x16_0_0_0 = 7
    I_16x16_1_0_0 = 8
    I_16x16_2_0_0 = 9
    I_16x16_3_0_0 = 10
    I_16x16_0_1_0 = 11
    I_16x16_1_1_0 = 12
    I_16x16_2_1_0 = 13
    I_16x16_3_1_0 = 14
    I_16x16_0_2_0 = 15
    I_16x16_1_2_0 = 16
    I_16x16_2_2_0 = 17
    I_16x16_3_2_0 = 18
    I_16x16_0_0_1 = 19
    I_16x16_1_0_1 = 20
    I_16x16_2_0_1 = 21
    I_16x16_3_0_1 = 22
    I_16x16_0_1_1 = 23
    I_16x16_1_1_1 = 24
    I_16x16_2_1_1 = 25
    I_16x16_3_1_1 = 26
    I_16x16_0_2_1 = 27
    I_16x16_1_2_1 = 28
    I_16x16_2_2_1 = 29
    I_16x16_3_2_1 = 30
    I_PCM = 31
}
enum subMbType_e {
    P_L0_8x8 = 0
    P_L0_8x4 = 1
    P_L0_4x8 = 2
    P_L0_4x4 = 3
}
struct mv_t {
    hor : int
    ver : int
}
struct mbPred_t {
    prevIntra4x4PredModeFlag : array<uint>
    remIntra4x4PredMode : array<uint>
    intraChromaPredMode : uint
    refIdxL0 : array<uint>
    mvdL0 : array<mv_t>
}
struct subMbPred_t {
    subMbType : array<subMbType_e>
    refIdxL0 : array<uint>
    mvdL0 : array<array<mv_t>>
}
struct residual_t {
    totalCoeff : array<int>
    level : array<array<int>>
    coeffMap : array<uint>
}
struct macroblockLayer_t {
    mbType : mbType_e
    codedBlockPattern : uint
    mbQpDelta : int
    mbPred : mbPred_t
    subMbPred : subMbPred_t
    residual : residual_t
}
struct mbStorage {
    mbType : mbType_e
    sliceId : uint
    disableDeblockingFilterIdc : uint
    filterOffsetA : int
    filterOffsetB : int
    qpY : uint
    chromaQpIndexOffset : int
    totalCoeff : array<int>
    intra4x4PredMode : array<uint8>
    refPic : array<uint>
    refAddr : array<uint8?>
    mv : array<mv_t>
    decoded : uint
    mbA : mbStorage?
    mbB : mbStorage?
    mbC : mbStorage?
    mbD : mbStorage?
}
struct mbStorage_t {
    mbType : mbType_e
    sliceId : uint
    disableDeblockingFilterIdc : uint
    filterOffsetA : int
    filterOffsetB : int
    qpY : uint
    chromaQpIndexOffset : int
    totalCoeff : array<int>
    intra4x4PredMode : array<uint8>
    refPic : array<uint>
    refAddr : array<uint8?>
    mv : array<mv_t>
    decoded : uint
    mbA : mbStorage?
    mbB : mbStorage?
    mbC : mbStorage?
    mbD : mbStorage?
}
struct pocStorage_t {
    prevPicOrderCntLsb : uint
    prevPicOrderCntMsb : int
    prevFrameNum : uint
    prevFrameNumOffset : uint
}
struct sliceStorage_t {
    sliceId : uint
    numDecodedMbs : uint
    lastMbAddr : uint
}
struct aubCheck_t {
    nuPrev : array<nalUnit_t>
    prevFrameNum : uint
    prevIdrPicId : uint
    prevPicOrderCntLsb : uint
    prevDeltaPicOrderCntBottom : int
    prevDeltaPicOrderCnt : array<int>
    firstCallFlag : uint
}
struct storage {
    oldSpsId : uint
    activePpsId : uint
    activeSpsId : uint
    activePps : picParamSet_t?
    activeSps : seqParamSet_t?
    sps : array<seqParamSet_t?>
    pps : array<picParamSet_t?>
    sliceGroupMap : uint?
    picSizeInMbs : uint
    skipRedundantSlices : uint
    picStarted : uint
    validSliceInAccessUnit : uint
    slice : array<sliceStorage_t>
    numConcealedMbs : uint
    currentPicId : uint
    mb : mbStorage_t?
    noReordering : uint
    dpb : array<dpbStorage_t>
    poc : array<pocStorage_t>
    aub : array<aubCheck_t>
    currImage : array<image_t>
    prevNalUnit : array<nalUnit_t>
    sliceHeader : array<sliceHeader_t>
    prevBufNotFinished : uint
    prevBufPointer : uint8?
    prevBytesConsumed : uint
    strm : array<strmData_t>
    mbLayer : macroblockLayer_t?
    pendingActivation : uint
    intraConcealmentFlag : uint
    conversionBuffer : uint?
    conversionBufferSize : size_t
}
struct storage_t {
    oldSpsId : uint
    activePpsId : uint
    activeSpsId : uint
    activePps : picParamSet_t?
    activeSps : seqParamSet_t?
    sps : array<seqParamSet_t?>
    pps : array<picParamSet_t?>
    sliceGroupMap : uint?
    picSizeInMbs : uint
    skipRedundantSlices : uint
    picStarted : uint
    validSliceInAccessUnit : uint
    slice : array<sliceStorage_t>
    numConcealedMbs : uint
    currentPicId : uint
    mb : mbStorage_t?
    noReordering : uint
    dpb : array<dpbStorage_t>
    poc : array<pocStorage_t>
    aub : array<aubCheck_t>
    currImage : array<image_t>
    prevNalUnit : array<nalUnit_t>
    sliceHeader : array<sliceHeader_t>
    prevBufNotFinished : uint
    prevBufPointer : uint8?
    prevBytesConsumed : uint
    strm : array<strmData_t>
    mbLayer : macroblockLayer_t?
    pendingActivation : uint
    intraConcealmentFlag : uint
    conversionBuffer : uint?
    conversionBufferSize : size_t
}
typedef boxsize_t = uint64
typedef MP4D_file_offset_t = uint64
struct MP4D_sample_to_chunk_t_tag {
    first_chunk : uint
    samples_per_chunk : uint
}
struct Unnamed {
    width : uint
    height : uint
}
struct Unnamed_0 {
    channelcount : uint
    samplerate_hz : uint
}
struct MP4D_track_t {
    sample_count : uint
    dsi : uint8?
    dsi_bytes : uint
    object_type_indication : uint
    handler_type : uint
    duration_hi : uint
    duration_lo : uint
    timescale : uint
    avg_bitrate_bps : uint
    language : array<uint8>
    stream_type : uint
    SampleDescription : Unnamed_1
    entry_size : uint?
    sample_to_chunk_count : uint
    sample_to_chunk : MP4D_sample_to_chunk_t_tag?
    chunk_count : uint
    chunk_offset : uint64?
    timestamp : uint?
    duration : uint?
}
struct MP4D_demux_tag {
    read_pos : int64
    read_size : int64
    track : MP4D_track_t?
    read_callback : function?
    token : uint64
    track_count : uint
    duration_hi : uint
    duration_lo : uint
    timescale : uint
    tag : Unnamed_2
}
struct Unnamed_2 {
    title : uint8?
    artist : uint8?
    album : uint8?
    year : uint8?
    comment : uint8?
    genre : uint8?
}
struct MP4D_demux_t {
    read_pos : int64
    read_size : int64
    track : MP4D_track_t?
    read_callback : function?
    token : uint64
    track_count : uint
    duration_hi : uint
    duration_lo : uint
    timescale : uint
    tag : Unnamed_2
}
struct DecodeSummary {
    combined_hash : uint
    first_hash : uint
    last_hash : uint
    frame_count : int
    width : int
    height : int
}
struct DecodeSummary {
    combined_hash : uint
    first_hash : uint
    last_hash : uint
    frame_count : int
    width : int
    height : int
}
struct DecoderState {
    storage : storage_t?
    width : int
    height : int
    picture : uint8?
}
struct DecoderState {
    storage : storage_t?
    width : int
    height : int
    picture : uint8?
}
struct MemoryInput {
    bytes : uint8 const?
    length : int
}
struct MemoryInput {
    bytes : uint8 const?
    length : int
}
[export]
def c2da___bswap_16(var c2da___bsx : uint16) : uint16 {
    return uint16(int(c2da___bsx) >> 8 & 255 | int(c2da___bsx) & 255 << 8)
}
[export]
def c2da___bswap_32(var c2da___bsx_0 : uint) : uint {
    return uint(c2da___bsx_0 & 0xff000000) >> uint(uint(24)) | uint(c2da___bsx_0 & 0xff0000) >> uint(uint(8)) | uint(c2da___bsx_0 & 0xff00) << uint(uint(8)) | uint(c2da___bsx_0 & 0xff) << uint(uint(24))
}
[export]
def c2da___bswap_64(var c2da___bsx_1 : uint64) : uint64 {
    return uint64(c2da___bsx_1 & 0xff00000000000000uL) >> uint64(uint64(56)) | uint64(c2da___bsx_1 & 0xff000000000000uL) >> uint64(uint64(40)) | uint64(c2da___bsx_1 & 0xff0000000000uL) >> uint64(uint64(24)) | uint64(c2da___bsx_1 & 0xff00000000uL) >> uint64(uint64(8)) | uint64(c2da___bsx_1 & uint64(0xff000000)) << uint64(uint64(8)) | uint64(c2da___bsx_1 & uint64(0xff0000)) << uint64(uint64(24)) | uint64(c2da___bsx_1 & uint64(0xff00)) << uint64(uint64(40)) | uint64(c2da___bsx_1 & uint64(0xff)) << uint64(uint64(56))
}
[export]
def c2da___uint16_identity(var c2da___x : uint16) : uint16 {
    return c2da___x
}
[export]
def c2da___uint32_identity(var c2da___x_0 : uint) : uint {
    return c2da___x_0
}
[export]
def c2da___uint64_identity(var c2da___x_1 : uint64) : uint64 {
    return c2da___x_1
}
var sample_mp4_len : uint const = 0x1f6c

var sample_mp4_bytes : array<uint8> const = [uint8(0), uint8(0), uint8(0), uint8(32), uint8(102), uint8(116), uint8(121), uint8(112), uint8(105), uint8(115), uint8(111), uint8(109), uint8(0), uint8(0), uint8(2), uint8(0), uint8(105), uint8(115), uint8(111), uint8(109), uint8(105), uint8(115), uint8(111), uint8(50), uint8(97), uint8(118), uint8(99), uint8(49), uint8(109), uint8(112), uint8(52), uint8(49), uint8(0), uint8(0), uint8(0), uint8(8), uint8(102), uint8(114), uint8(101), uint8(101), uint8(0), uint8(0), uint8(27), uint8(241), uint8(109), uint8(100), uint8(97), uint8(116), uint8(0), uint8(0), uint8(2), uint8(113), uint8(6), uint8(5), uint8(255), uint8(255), uint8(109), uint8(220), uint8(69), uint8(233), uint8(189), uint8(230), uint8(217), uint8(72), uint8(183), uint8(150), uint8(44), uint8(216), uint8(32), uint8(217), uint8(35), uint8(238), uint8(239), uint8(120), uint8(50), uint8(54), uint8(52), uint8(32), uint8(45), uint8(32), uint8(99), uint8(111), uint8(114), uint8(101), uint8(32), uint8(49), uint8(54), uint8(53), uint8(32), uint8(114), uint8(51), uint8(50), uint8(50), uint8(50), uint8(32), uint8(98), uint8(51), uint8(53), uint8(54), uint8(48), uint8(53), uint8(97), uint8(32), uint8(45), uint8(32), uint8(72), uint8(46), uint8(50), uint8(54), uint8(52), uint8(47), uint8(77), uint8(80), uint8(69), uint8(71), uint8(45), uint8(52), uint8(32), uint8(65), uint8(86), uint8(67), uint8(32), uint8(99), uint8(111), uint8(100), uint8(101), uint8(99), uint8(32), uint8(45), uint8(32), uint8(67), uint8(111), uint8(112), uint8(121), uint8(108), uint8(101), uint8(102), uint8(116), uint8(32), uint8(50), uint8(48), uint8(48), uint8(51), uint8(45), uint8(50), uint8(48), uint8(50), uint8(53), uint8(32), uint8(45), uint8(32), uint8(104), uint8(116), uint8(116), uint8(112), uint8(58), uint8(47), uint8(47), uint8(119), uint8(119), uint8(119), uint8(46), uint8(118), uint8(105), uint8(100), uint8(101), uint8(111), uint8(108), uint8(97), uint8(110), uint8(46), uint8(111), uint8(114), uint8(103), uint8(47), uint8(120), uint8(50), uint8(54), uint8(52), uint8(46), uint8(104), uint8(116), uint8(109), uint8(108), uint8(32), uint8(45), uint8(32), uint8(111), uint8(112), uint8(116), uint8(105), uint8(111), uint8(110), uint8(115), uint8(58), uint8(32), uint8(99), uint8(97), uint8(98), uint8(97), uint8(99), uint8(61), uint8(48), uint8(32), uint8(114), uint8(101), uint8(102), uint8(61), uint8(51), uint8(32), uint8(100), uint8(101), uint8(98), uint8(108), uint8(111), uint8(99), uint8(107), uint8(61), uint8(49), uint8(58), uint8(48), uint8(58), uint8(48), uint8(32), uint8(97), uint8(110), uint8(97), uint8(108), uint8(121), uint8(115), uint8(101), uint8(61), uint8(48), uint8(120), uint8(49), uint8(58), uint8(48), uint8(120), uint8(49), uint8(49), uint8(49), uint8(32), uint8(109), uint8(101), uint8(61), uint8(104), uint8(101), uint8(120), uint8(32), uint8(115), uint8(117), uint8(98), uint8(109), uint8(101), uint8(61), uint8(55), uint8(32), uint8(112), uint8(115), uint8(121), uint8(61), uint8(49), uint8(32), uint8(112), uint8(115), uint8(121), uint8(95), uint8(114), uint8(100), uint8(61), uint8(49), uint8(46), uint8(48), uint8(48), uint8(58), uint8(48), uint8(46), uint8(48), uint8(48), uint8(32), uint8(109), uint8(105), uint8(120), uint8(101), uint8(100), uint8(95), uint8(114), uint8(101), uint8(102), uint8(61), uint8(49), uint8(32), uint8(109), uint8(101), uint8(95), uint8(114), uint8(97), uint8(110), uint8(103), uint8(101), uint8(61), uint8(49), uint8(54), uint8(32), uint8(99), uint8(104), uint8(114), uint8(111), uint8(109), uint8(97), uint8(95), uint8(109), uint8(101), uint8(61), uint8(49), uint8(32), uint8(116), uint8(114), uint8(101), uint8(108), uint8(108), uint8(105), uint8(115), uint8(61), uint8(49), uint8(32), uint8(56), uint8(120), uint8(56), uint8(100), uint8(99), uint8(116), uint8(61), uint8(48), uint8(32), uint8(99), uint8(113), uint8(109), uint8(61), uint8(48), uint8(32), uint8(100), uint8(101), uint8(97), uint8(100), uint8(122), uint8(111), uint8(110), uint8(101), uint8(61), uint8(50), uint8(49), uint8(44), uint8(49), uint8(49), uint8(32), uint8(102), uint8(97), uint8(115), uint8(116), uint8(95), uint8(112), uint8(115), uint8(107), uint8(105), uint8(112), uint8(61), uint8(49), uint8(32), uint8(99), uint8(104), uint8(114), uint8(111), uint8(109), uint8(97), uint8(95), uint8(113), uint8(112), uint8(95), uint8(111), uint8(102), uint8(102), uint8(115), uint8(101), uint8(116), uint8(61), uint8(45), uint8(50), uint8(32), uint8(116), uint8(104), uint8(114), uint8(101), uint8(97), uint8(100), uint8(115), uint8(61), uint8(50), uint8(32), uint8(108), uint8(111), uint8(111), uint8(107), uint8(97), uint8(104), uint8(101), uint8(97), uint8(100), uint8(95), uint8(116), uint8(104), uint8(114), uint8(101), uint8(97), uint8(100), uint8(115), uint8(61), uint8(49), uint8(32), uint8(115), uint8(108), uint8(105), uint8(99), uint8(101), uint8(100), uint8(95), uint8(116), uint8(104), uint8(114), uint8(101), uint8(97), uint8(100), uint8(115), uint8(61), uint8(48), uint8(32), uint8(110), uint8(114), uint8(61), uint8(48), uint8(32), uint8(100), uint8(101), uint8(99), uint8(105), uint8(109), uint8(97), uint8(116), uint8(101), uint8(61), uint8(49), uint8(32), uint8(105), uint8(110), uint8(116), uint8(101), uint8(114), uint8(108), uint8(97), uint8(99), uint8(101), uint8(100), uint8(61), uint8(48), uint8(32), uint8(98), uint8(108), uint8(117), uint8(114), uint8(97), uint8(121), uint8(95), uint8(99), uint8(111), uint8(109), uint8(112), uint8(97), uint8(116), uint8(61), uint8(48), uint8(32), uint8(99), uint8(111), uint8(110), uint8(115), uint8(116), uint8(114), uint8(97), uint8(105), uint8(110), uint8(101), uint8(100), uint8(95), uint8(105), uint8(110), uint8(116), uint8(114), uint8(97), uint8(61), uint8(48), uint8(32), uint8(98), uint8(102), uint8(114), uint8(97), uint8(109), uint8(101), uint8(115), uint8(61), uint8(48), uint8(32), uint8(119), uint8(101), uint8(105), uint8(103), uint8(104), uint8(116), uint8(112), uint8(61), uint8(48), uint8(32), uint8(107), uint8(101), uint8(121), uint8(105), uint8(110), uint8(116), uint8(61), uint8(50), uint8(53), uint8(48), uint8(32), uint8(107), uint8(101), uint8(121), uint8(105), uint8(110), uint8(116), uint8(95), uint8(109), uint8(105), uint8(110), uint8(61), uint8(49), uint8(50), uint8(32), uint8(115), uint8(99), uint8(101), uint8(110), uint8(101), uint8(99), uint8(117), uint8(116), uint8(61), uint8(52), uint8(48), uint8(32), uint8(105), uint8(110), uint8(116), uint8(114), uint8(97), uint8(95), uint8(114), uint8(101), uint8(102), uint8(114), uint8(101), uint8(115), uint8(104), uint8(61), uint8(48), uint8(32), uint8(114), uint8(99), uint8(95), uint8(108), uint8(111), uint8(111), uint8(107), uint8(97), uint8(104), uint8(101), uint8(97), uint8(100), uint8(61), uint8(52), uint8(48), uint8(32), uint8(114), uint8(99), uint8(61), uint8(99), uint8(114), uint8(102), uint8(32), uint8(109), uint8(98), uint8(116), uint8(114), uint8(101), uint8(101), uint8(61), uint8(49), uint8(32), uint8(99), uint8(114), uint8(102), uint8(61), uint8(50), uint8(51), uint8(46), uint8(48), uint8(32), uint8(113), uint8(99), uint8(111), uint8(109), uint8(112), uint8(61), uint8(48), uint8(46), uint8(54), uint8(48), uint8(32), uint8(113), uint8(112), uint8(109), uint8(105), uint8(110), uint8(61), uint8(48), uint8(32), uint8(113), uint8(112), uint8(109), uint8(97), uint8(120), uint8(61), uint8(54), uint8(57), uint8(32), uint8(113), uint8(112), uint8(115), uint8(116), uint8(101), uint8(112), uint8(61), uint8(52), uint8(32), uint8(105), uint8(112), uint8(95), uint8(114), uint8(97), uint8(116), uint8(105), uint8(111), uint8(61), uint8(49), uint8(46), uint8(52), uint8(48), uint8(32), uint8(97), uint8(113), uint8(61), uint8(49), uint8(58), uint8(49), uint8(46), uint8(48), uint8(48), uint8(0), uint8(128), uint8(0), uint8(0), uint8(6), uint8(205), uint8(101), uint8(136), uint8(132), uint8(55), uint8(196), uint8(34), uint8(42), uint8(224), uint8(192), uint8(133), uint8(248), uint8(8), uint8(83), uint8(34), uint8(0), uint8(1), uint8(0), uint8(154), uint8(212), uint8(24), uint8(96), uint8(0), uint8(241), uint8(120), uint8(206), uint8(140), uint8(104), uint8(232), uint8(23), uint8(221), uint8(255), uint8(226), uint8(103), uint8(220), uint8(153), uint8(17), uint8(138), uint8(191), uint8(176), uint8(111), uint8(254), uint8(210), uint8(94), uint8(97), uint8(162), uint8(50), uint8(176), uint8(246), uint8(207), uint8(251), uint8(8), uint8(252), uint8(69), uint8(150), uint8(100), uint8(62), uint8(206), uint8(66), uint8(95), uint8(246), uint8(11), uint8(52), uint8(184), uint8(169), uint8(4), uint8(178), uint8(39), uint8(251), uint8(107), uint8(141), uint8(67), uint8(19), uint8(147), uint8(229), uint8(225), uint8(234), uint8(245), uint8(43), uint8(140), uint8(26), uint8(50), uint8(132), uint8(221), uint8(94), uint8(160), uint8(117), uint8(153), uint8(180), uint8(112), uint8(95), uint8(143), uint8(239), uint8(148), uint8(28), uint8(84), uint8(93), uint8(84), uint8(19), uint8(55), uint8(251), uint8(224), uint8(64), uint8(0), uint8(88), uint8(0), uint8(193), uint8(77), uint8(132), uint8(0), uint8(9), uint8(120), uint8(0), uint8(8), uint8(4), uint8(0), uint8(9), uint8(243), uint8(48), uint8(171), uint8(49), uint8(208), uint8(33), uint8(23), uint8(202), uint8(155), uint8(7), uint8(134), uint8(185), uint8(209), uint8(164), uint8(247), uint8(32), uint8(56), uint8(159), uint8(255), uint8(180), uint8(224), uint8(87), uint8(49), uint8(37), uint8(136), uint8(210), uint8(0), uint8(55), uint8(92), uint8(81), uint8(85), uint8(133), uint8(69), uint8(160), uint8(2), uint8(13), uint8(42), uint8(116), uint8(189), uint8(86), uint8(192), uint8(35), uint8(13), uint8(255), uint8(251), uint8(199), uint8(1), uint8(78), uint8(229), uint8(178), uint8(35), uint8(74), uint8(34), uint8(160), uint8(35), uint8(241), uint8(118), uint8(166), uint8(80), uint8(56), uint8(128), uint8(64), uint8(51), uint8(47), uint8(249), uint8(50), uint8(18), uint8(147), uint8(188), uint8(117), uint8(131), uint8(7), uint8(192), uint8(1), uint8(226), uint8(240), uint8(206), uint8(140), uint8(108), uint8(84), uint8(11), uint8(229), uint8(127), uint8(250), uint8(227), uint8(80), uint8(198), uint8(228), uint8(249), uint8(104), uint8(61), uint8(94), uint8(6), uint8(173), uint8(98), uint8(86), uint8(43), uint8(20), uint8(33), uint8(234), uint8(244), uint8(128), uint8(53), uint8(153), uint8(146), uint8(56), uint8(63), uint8(191), uint8(191), uint8(245), uint8(194), uint8(50), uint8(43), uint8(57), uint8(74), uint8(131), uint8(168), uint8(7), uint8(235), uint8(120), uint8(179), uint8(103), uint8(124), uint8(93), uint8(148), uint8(89), uint8(102), uint8(131), uint8(169), uint8(143), uint8(33), uint8(239), uint8(244), uint8(224), uint8(134), uint8(116), uint8(33), uint8(76), uint8(232), uint8(58), uint8(172), uint8(26), uint8(124), uint8(84), uint8(176), uint8(37), uint8(186), uint8(127), uint8(190), uint8(3), uint8(3), uint8(120), uint8(72), uint8(0), uint8(8), uint8(24), uint8(160), uint8(0), uint8(8), uint8(19), uint8(134), uint8(194), uint8(236), uint8(128), uint8(51), uint8(240), uint8(122), uint8(108), uint8(85), uint8(152), uint8(6), uint8(45), uint8(3), uint8(216), uint8(75), uint8(38), uint8(82), uint8(5), uint8(165), uint8(127), uint8(223), uint8(96), uint8(212), uint8(102), uint8(122), uint8(3), uint8(214), uint8(183), uint8(239), uint8(130), uint8(108), uint8(6), uint8(214), uint8(20), uint8(160), uint8(63), uint8(39), uint8(213), uint8(80), uint8(26), uint8(248), uint8(199), uint8(1), uint8(117), uint8(62), uint8(193), uint8(184), uint8(200), uint8(217), uint8(128), uint8(253), uint8(134), uint8(253), uint8(246), uint8(4), uint8(188), uint8(140), uint8(215), uint8(40), uint8(37), uint8(194), uint8(127), uint8(252), uint8(136), uint8(171), uint8(136), uint8(168), uint8(19), uint8(101), uint8(97), uint8(224), uint8(113), uint8(0), uint8(128), uint8(102), uint8(95), uint8(242), uint8(100), uint8(152), uint8(93), uint8(226), uint8(252), uint8(55), uint8(17), uint8(120), uint8(203), uint8(152), uint8(145), uint8(240), uint8(254), uint8(239), uint8(255), uint8(127), uint8(201), uint8(145), uint8(24), uint8(93), uint8(239), uint8(249), uint8(3), uint8(184), uint8(212), uint8(49), uint8(185), uint8(62), uint8(90), uint8(143), uint8(87), uint8(182), uint8(82), uint8(57), uint8(32), uint8(123), uint8(59), uint8(51), uint8(255), uint8(168), uint8(15), uint8(144), uint8(140), uint8(152), uint8(160), uint8(47), uint8(223), uint8(247), uint8(203), uint8(3), uint8(206), uint8(71), uint8(74), uint8(80), uint8(36), uint8(102), uint8(255), uint8(125), uint8(113), uint8(168), uint8(99), uint8(114), uint8(124), uint8(190), uint8(61), uint8(94), uint8(6), uint8(186), uint8(197), uint8(216), uint8(172), uint8(86), uint8(61), uint8(94), uint8(160), uint8(107), uint8(146), uint8(145), uint8(7), uint8(151), uint8(239), uint8(251), uint8(211), uint8(145), uint8(147), uint8(179), uint8(151), uint8(160), uint8(234), uint8(14), uint8(96), uint8(6), uint8(4), uint8(128), uint8(72), uint8(0), uint8(6), uint8(105), uint8(1), uint8(212), uint8(10), uint8(88), uint8(218), uint8(152), uint8(108), uint8(0), uint8(249), uint8(112), uint8(57), uint8(246), uint8(15), uint8(48), uint8(5), uint8(241), uint8(13), uint8(184), uint8(218), uint8(158), uint8(9), uint8(50), uint8(52), uint8(136), uint8(41), uint8(58), uint8(254), uint8(243), uint8(62), uint8(208), uint8(37), uint8(27), uint8(83), uint8(26), uint8(248), uint8(197), uint8(159), uint8(93), uint8(140), uint8(12), uint8(215), uint8(193), uint8(101), uint8(241), uint8(189), uint8(57), uint8(129), uint8(252), uint8(232), uint8(189), uint8(69), uint8(153), uint8(174), uint8(253), uint8(236), uint8(113), uint8(21), uint8(123), uint8(36), uint8(191), uint8(6), uint8(144), uint8(0), uint8(16), uint8(53), uint8(101), uint8(224), uint8(0), uint8(240), uint8(189), uint8(56), uint8(188), uint8(167), uint8(82), uint8(248), uint8(213), uint8(157), uint8(255), uint8(239), uint8(205), uint8(72), uint8(50), uint8(51), uint8(137), uint8(107), uint8(157), uint8(218), uint8(238), uint8(33), uint8(122), uint8(113), uint8(121), uint8(78), uint8(165), uint8(241), uint8(235), uint8(59), uint8(255), uint8(192), uint8(174), uint8(47), uint8(204), uint8(198), uint8(17), uint8(78), uint8(81), uint8(234), uint8(247), uint8(59), uint8(9), uint8(31), uint8(35), uint8(15), uint8(156), uint8(182), uint8(43), uint8(255), uint8(214), uint8(28), uint8(22), uint8(31), uint8(85), uint8(156), uint8(222), uint8(151), uint8(127), uint8(172), uint8(13), uint8(186), uint8(11), uint8(211), uint8(6), uint8(105), uint8(215), uint8(253), uint8(245), uint8(168), uint8(123), uint8(28), uint8(17), uint8(77), uint8(88), uint8(222), uint8(30), uint8(175), uint8(91), uint8(133), uint8(241), uint8(193), uint8(84), uint8(197), uint8(140), uint8(233), uint8(234), uint8(244), uint8(128), uint8(0), uint8(243), uint8(24), uint8(205), uint8(142), uint8(0), uint8(171), uint8(127), uint8(127), uint8(237), uint8(0), uint8(120), uint8(230), uint8(59), uint8(115), uint8(128), uint8(34), uint8(151), uint8(253), uint8(240), uint8(32), uint8(64), uint8(0), uint8(64), uint8(33), uint8(128), uint8(0), uint8(160), uint8(136), uint8(6), uint8(91), uint8(147), uint8(176), uint8(9), uint8(180), uint8(229), uint8(16), uint8(42), uint8(196), uint8(196), uint8(192), uint8(9), uint8(149), uint8(128), uint8(12), uint8(54), uint8(167), uint8(128), uint8(217), uint8(14), uint8(83), uint8(169), uint8(0), uint8(185), uint8(54), uint8(239), uint8(223), uint8(48), uint8(0), uint8(4), uint8(142), uint8(193), uint8(132), uint8(82), uint8(99), uint8(106), uint8(115), uint8(86), uint8(248), uint8(131), uint8(243), uint8(236), uint8(206), uint8(53), uint8(200), uint8(56), uint8(218), uint8(158), uint8(5), uint8(251), uint8(35), uint8(101), uint8(9), uint8(113), uint8(9), uint8(253), uint8(243), uint8(0), uint8(2), uint8(202), uint8(41), uint8(55), uint8(3), uint8(106), uint8(113), uint8(21), uint8(1), uint8(31), uint8(109), uint8(141), uint8(51), uint8(1), uint8(208), uint8(32), uint8(102), uint8(95), uint8(114), uint8(100), uint8(152), uint8(187), uint8(175), uint8(198), uint8(255), uint8(224), uint8(248), uint8(0), uint8(82), uint8(241), uint8(190), uint8(98), uint8(71), uint8(194), uint8(251), uint8(191), uint8(253), uint8(75), uint8(163), uint8(4), uint8(142), uint8(161), uint8(85), uint8(171), uint8(199), uint8(157), uint8(7), uint8(230), uint8(100), uint8(135), uint8(226), uint8(207), uint8(246), uint8(192), uint8(229), uint8(198), uint8(200), uint8(74), uint8(233), uint8(171), uint8(203), uint8(105), uint8(78), uint8(80), uint8(27), uint8(16), uint8(226), uint8(111), uint8(244), uint8(9), uint8(101), uint8(180), uint8(159), uint8(165), uint8(84), uint8(30), uint8(185), uint8(210), uint8(195), uint8(113), uint8(191), uint8(190), uint8(192), uint8(193), uint8(167), uint8(10), uint8(0), uint8(11), uint8(129), uint8(131), uint8(16), uint8(31), uint8(42), uint8(32), uint8(75), uint8(79), uint8(171), uint8(96), uint8(116), uint8(170), uint8(129), uint8(41), uint8(62), uint8(194), uint8(45), uint8(28), uint8(161), uint8(25), uint8(41), uint8(127), uint8(252), uint8(211), uint8(22), uint8(95), uint8(245), uint8(97), uint8(242), uint8(169), uint8(15), uint8(255), uint8(21), uint8(54), uint8(4), uint8(36), uint8(79), uint8(10), uint8(30), uint8(2), uint8(18), uint8(103), uint8(128), uint8(110), uint8(115), uint8(45), uint8(227), uint8(58), uint8(194), uint8(127), uint8(249), uint8(133), uint8(229), uint8(144), uint8(210), uint8(201), uint8(143), uint8(212), uint8(69), uint8(92), uint8(69), uint8(65), uint8(220), uint8(164), uint8(62), uint8(96), uint8(58), uint8(33), uint8(153), uint8(123), uint8(197), uint8(90), uint8(219), uint8(226), uint8(223), uint8(224), uint8(40), uint8(137), uint8(200), uint8(167), uint8(15), uint8(183), uint8(127), uint8(176), uint8(26), uint8(90), uint8(76), uint8(183), uint8(186), uint8(255), uint8(237), uint8(200), uint8(156), uint8(138), uint8(112), uint8(251), uint8(119), uint8(250), uint8(185), uint8(98), uint8(77), uint8(159), uint8(151), uint8(236), uint8(84), uint8(234), uint8(58), uint8(105), uint8(95), uint8(245), uint8(15), uint8(73), uint8(83), uint8(3), uint8(251), uint8(251), uint8(229), uint8(14), uint8(105), uint8(219), uint8(2), uint8(223), uint8(251), uint8(229), uint8(106), uint8(197), uint8(151), uint8(159), uint8(106), uint8(245), uint8(102), uint8(199), uint8(147), uint8(155), uint8(234), uint8(244), uint8(131), uint8(164), uint8(169), uint8(129), uint8(247), uint8(247), uint8(254), uint8(208), uint8(230), uint8(157), uint8(176), uint8(44), uint8(191), uint8(223), uint8(4), uint8(8), uint8(116), uint8(32), uint8(0), uint8(8), uint8(1), uint8(128), uint8(14), uint8(154), uint8(74), uint8(240), uint8(67), uint8(106), uint8(100), uint8(165), uint8(120), uint8(33), uint8(181), uint8(54), uint8(2), uint8(185), uint8(137), uint8(40), uint8(218), uint8(152), uint8(128), uint8(174), uint8(98), uint8(74), uint8(54), uint8(166), uint8(76), uint8(3), uint8(231), uint8(14), uint8(54), uint8(166), uint8(76), uint8(3), uint8(231), uint8(14), uint8(54), uint8(166), uint8(192), uint8(10), uint8(114), uint8(158), uint8(193), uint8(181), uint8(49), uint8(0), uint8(41), uint8(202), uint8(123), uint8(6), uint8(212), uint8(224), uint8(0), uint8(2), uint8(53), uint8(8), uint8(125), uint8(134), uint8(133), uint8(185), uint8(123), uint8(55), uint8(192), uint8(31), uint8(183), uint8(130), uint8(39), uint8(213), uint8(117), uint8(3), uint8(32), uint8(48), uint8(0), uint8(129), uint8(89), uint8(0), uint8(12), uint8(72), uint8(14), uint8(5), uint8(128), uint8(124), uint8(71), uint8(128), uint8(112), uint8(28), uint8(3), uint8(96), uint8(32), uint8(138), uint8(11), uint8(64), uint8(5), uint8(96), uint8(104), uint8(226), uint8(80), uint8(28), uint8(1), uint8(176), uint8(226), uint8(32), uint8(28), uint8(48), uint8(241), uint8(197), uint8(231), uint8(182), uint8(76), uint8(203), uint8(243), uint8(223), uint8(124), uint8(12), uint8(1), uint8(57), uint8(3), uint8(8), uint8(16), uint8(0), uint8(148), uint8(93), uint8(248), uint8(63), uint8(104), uint8(100), uint8(212), uint8(249), uint8(192), uint8(252), uint8(155), uint8(255), uint8(235), uint8(133), uint8(13), uint8(55), uint8(127), uint8(243), uint8(254), uint8(40), uint8(28), uint8(13), uint8(6), uint8(16), uint8(52), uint8(52), uint8(125), uint8(246), uint8(15), uint8(248), uint8(135), uint8(163), uint8(158), uint8(127), uint8(128), uint8(147), uint8(225), uint8(196), uint8(127), uint8(70), uint8(187), uint8(154), uint8(239), uint8(38), uint8(62), uint8(35), uint8(254), uint8(131), uint8(66), uint8(76), uint8(251), uint8(117), uint8(127), uint8(252), uint8(129), uint8(94), uint8(155), uint8(32), uint8(78), uint8(203), uint8(206), uint8(244), uint8(195), uint8(2), uint8(112), uint8(26), uint8(32), uint8(0), uint8(128), uint8(150), uint8(183), uint8(73), uint8(136), uint8(151), uint8(225), uint8(111), uint8(61), uint8(225), uint8(31), uint8(255), uint8(162), uint8(53), uint8(137), uint8(126), uint8(43), uint8(84), uint8(157), uint8(88), uint8(174), uint8(59), uint8(195), uint8(30), uint8(187), uint8(160), uint8(0), uint8(79), uint8(134), uint8(176), uint8(169), uint8(217), uint8(37), uint8(240), uint8(206), uint8(51), uint8(104), uint8(63), uint8(156), uint8(186), uint8(146), uint8(195), uint8(0), uint8(20), uint8(5), uint8(132), uint8(1), uint8(87), uint8(1), uint8(155), uint8(56), uint8(104), uint8(101), uint8(17), uint8(197), uint8(104), uint8(216), uint8(60), uint8(230), uint8(92), uint8(46), uint8(202), uint8(13), uint8(33), uint8(57), uint8(91), uint8(247), uint8(119), uint8(31), uint8(52), uint8(140), uint8(93), uint8(142), uint8(80), uint8(26), uint8(122), uint8(103), uint8(56), uint8(120), uint8(96), uint8(22), uint8(4), uint8(198), uint8(30), uint8(126), uint8(171), uint8(254), uint8(160), uint8(1), uint8(75), uint8(204), uint8(121), uint8(26), uint8(46), uint8(58), uint8(147), uint8(255), uint8(218), uint8(135), uint8(125), uint8(164), uint8(167), uint8(65), uint8(163), uint8(20), uint8(219), uint8(239), uint8(86), uint8(11), uint8(107), uint8(70), uint8(160), uint8(185), uint8(175), uint8(246), uint8(193), uint8(8), uint8(1), uint8(41), uint8(128), uint8(192), uint8(3), uint8(192), uint8(14), uint8(24), uint8(204), uint8(109), uint8(180), uint8(129), uint8(236), uint8(23), uint8(146), uint8(54), uint8(226), uint8(13), uint8(13), uint8(255), uint8(251), uint8(192), uint8(195), uint8(34), uint8(248), uint8(147), uint8(105), uint8(240), uint8(2), uint8(29), uint8(93), uint8(124), uint8(7), uint8(29), uint8(194), uint8(51), uint8(22), uint8(159), uint8(41), uint8(31), uint8(206), uint8(88), uint8(97), uint8(128), uint8(127), uint8(193), uint8(88), uint8(156), uint8(4), uint8(200), uint8(157), uint8(137), uint8(90), uint8(187), uint8(3), uint8(128), uint8(1), uint8(12), uint8(3), uint8(132), uint8(16), uint8(0), uint8(118), uint8(128), uint8(10), uint8(0), uint8(202), uint8(109), uint8(158), uint8(100), uint8(96), uint8(68), uint8(100), uint8(150), uint8(30), uint8(0), uint8(66), uint8(104), uint8(208), uint8(106), uint8(132), uint8(27), uint8(156), uint8(89), uint8(68), uint8(0), uint8(8), uint8(97), uint8(50), uint8(195), uint8(248), uint8(6), uint8(0), uint8(28), uint8(3), uint8(97), uint8(178), uint8(96), uint8(114), uint8(3), uint8(6), uint8(101), uint8(226), uint8(128), uint8(60), uint8(72), uint8(0), uint8(104), uint8(72), uint8(0), uint8(8), uint8(1), uint8(160), uint8(228), uint8(24), uint8(146), uint8(195), uint8(144), uint8(98), uint8(75), uint8(28), uint8(32), uint8(118), uint8(7), uint8(4), uint8(12), uint8(192), uint8(112), uint8(138), uint8(68), uint8(176), uint8(225), uint8(20), uint8(137), uint8(99), uint8(128), uint8(64), uint8(43), uint8(3), uint8(128), uint8(32), uint8(17), uint8(142), uint8(1), uint8(0), uint8(255), uint8(193), uint8(89), uint8(48), uint8(60), uint8(24), uint8(102), uint8(88), uint8(72), uint8(16), uint8(192), uint8(240), uint8(128), uint8(64), uint8(10), uint8(192), uint8(12), uint8(14), uint8(19), uint8(141), uint8(44), uint8(128), uint8(156), uint8(105), uint8(127), uint8(174), uint8(235), uint8(190), uint8(64), uint8(1), uint8(128), uint8(127), uint8(176), uint8(86), uint8(80), uint8(21), uint8(99), uint8(14), uint8(100), uint8(74), uint8(178), uint8(40), uint8(41), uint8(149), uint8(134), uint8(0), uint8(2), uint8(2), uint8(108), uint8(0), uint8(2), uint8(4), uint8(144), uint8(200), uint8(180), uint8(28), uint8(1), uint8(16), uint8(250), uint8(160), uint8(28), uint8(4), uint8(99), uint8(98), uint8(137), uint8(145), uint8(65), uint8(73), uint8(43), uint8(122), uint8(105), uint8(158), uint8(3), uint8(128), uint8(67), uint8(190), uint8(73), uint8(48), uint8(60), uint8(6), uint8(51), uint8(35), uint8(129), uint8(35), uint8(134), uint8(204), uint8(131), uint8(182), uint8(95), uint8(162), uint8(123), uint8(224), uint8(96), uint8(3), uint8(67), uint8(132), uint8(128), uint8(0), uint8(128), uint8(139), uint8(0), uint8(0), uint8(128), uint8(0), uint8(24), uint8(240), uint8(86), uint8(207), uint8(8), uint8(66), uint8(178), uint8(207), uint8(2), uint8(206), uint8(0), uint8(153), uint8(0), uint8(150), uint8(102), uint8(88), uint8(216), uint8(233), uint8(187), uint8(74), uint8(60), uint8(65), uint8(221), uint8(156), uint8(181), uint8(102), uint8(115), uint8(157), uint8(192), uint8(32), uint8(16), uint8(130), uint8(225), uint8(39), uint8(196), uint8(241), uint8(254), uint8(92), uint8(123), uint8(138), uint8(0), uint8(7), uint8(160), uint8(9), uint8(237), uint8(41), uint8(85), uint8(175), uint8(159), uint8(216), uint8(66), uint8(5), uint8(134), uint8(8), uint8(0), uint8(10), uint8(0), uint8(135), uint8(135), uint8(154), uint8(135), uint8(217), uint8(202), uint8(73), uint8(164), uint8(184), uint8(85), uint8(32), uint8(209), uint8(54), uint8(16), uint8(32), uint8(150), uint8(89), uint8(2), uint8(9), uint8(229), uint8(128), uint8(172), uint8(36), uint8(206), uint8(47), uint8(163), uint8(119), uint8(179), uint8(192), uint8(35), uint8(116), uint8(100), uint8(50), uint8(24), uint8(124), uint8(41), uint8(227), uint8(17), uint8(221), uint8(163), uint8(65), uint8(44), uint8(99), uint8(24), uint8(255), uint8(240), uint8(195), uint8(176), uint8(84), uint8(9), uint8(4), uint8(0), uint8(2), uint8(128), uint8(168), uint8(64), uint8(0), uint8(52), uint8(2), uint8(172), uint8(28), uint8(64), uint8(9), uint8(128), uint8(114), uint8(0), uint8(108), uint8(96), uint8(224), uint8(32), uint8(102), uint8(1), uint8(192), uint8(129), uint8(216), uint8(51), uint8(4), uint8(113), uint8(172), uint8(96), uint8(3), uint8(195), uint8(0), uint8(255), uint8(216), uint8(43), uint8(131), uint8(145), uint8(255), uint8(68), uint8(148), uint8(92), uint8(92), uint8(92), uint8(92), uint8(92), uint8(92), uint8(92), uint8(95), uint8(12), uint8(3), uint8(255), uint8(96), uint8(174), uint8(47), uint8(196), uint8(0), uint8(18), uint8(68), uint8(0), uint8(8), uint8(145), uint8(89), uint8(108), uint8(86), uint8(43), uint8(17), uint8(96), uint8(128), uint8(4), uint8(186), uint8(225), uint8(214), uint8(3), uint8(128), uint8(37), uint8(215), uint8(32), uint8(28), uint8(63), uint8(246), uint8(10), uint8(226), uint8(191), uint8(196), uint8(0), uint8(1), uint8(6), uint8(80), uint8(0), uint8(16), uint8(68), uint8(136), uint8(0), uint8(2), uint8(60), uint8(0), uint8(0), uint8(35), uint8(147), uint8(45), uint8(25), uint8(96), uint8(16), uint8(0), uint8(16), uint8(49), uint8(96), uint8(84), uint8(99), uint8(128), uint8(64), uint8(0), uint8(64), uint8(197), uint8(130), uint8(0), uint8(151), uint8(92), uint8(32), uint8(0), uint8(4), uint8(35), uint8(232), uint8(0), uint8(8), uint8(200), uint8(92), uint8(14), uint8(4), uint8(186), uint8(224), uint8(112), uint8(0), uint8(16), uint8(143), uint8(160), uint8(0), uint8(35), uint8(33), uint8(114), uint8(0), uint8(0), uint8(1), uint8(202), uint8(65), uint8(154), uint8(56), uint8(111), uint8(227), uint8(97), uint8(110), uint8(34), uint8(31), uint8(127), uint8(2), uint8(20), uint8(241), uint8(202), uint8(12), uint8(156), uint8(247), uint8(153), uint8(35), uint8(13), uint8(60), uint8(189), uint8(247), uint8(191), uint8(132), uint8(0), uint8(6), uint8(65), uint8(196), uint8(162), uint8(16), uint8(1), uint8(17), uint8(72), uint8(0), uint8(10), uint8(72), uint8(136), uint8(129), uint8(145), uint8(133), uint8(45), uint8(5), uint8(158), uint8(123), uint8(120), uint8(189), uint8(36), uint8(210), uint8(215), uint8(126), uint8(150), uint8(219), uint8(87), uint8(141), uint8(82), uint8(169), uint8(112), uint8(0), uint8(103), uint8(23), uint8(137), uint8(122), uint8(17), uint8(76), uint8(35), uint8(35), uint8(159), uint8(252), uint8(186), uint8(195), uint8(121), uint8(254), uint8(22), uint8(47), uint8(33), uint8(76), uint8(195), uint8(47), uint8(8), uint8(214), uint8(151), uint8(69), uint8(127), uint8(253), uint8(59), uint8(249), uint8(226), uint8(95), uint8(218), uint8(95), uint8(225), uint8(142), uint8(18), uint8(81), uint8(175), uint8(4), uint8(93), uint8(26), uint8(171), uint8(137), uint8(151), uint8(4), uint8(126), uint8(79), uint8(222), uint8(1), uint8(15), uint8(151), uint8(57), uint8(234), uint8(94), uint8(127), uint8(111), uint8(52), uint8(104), uint8(206), uint8(0), uint8(21), uint8(232), uint8(148), uint8(220), uint8(126), uint8(87), uint8(221), uint8(26), uint8(166), uint8(141), uint8(124), uint8(231), uint8(187), uint8(246), uint8(110), uint8(50), uint8(40), uint8(251), uint8(246), uint8(244), uint8(9), uint8(90), uint8(53), uint8(238), uint8(118), uint8(83), uint8(250), uint8(94), uint8(100), uint8(207), uint8(1), uint8(56), uint8(227), uint8(230), uint8(6), uint8(220), uint8(53), uint8(248), uint8(163), uint8(131), uint8(84), uint8(195), uint8(197), uint8(104), uint8(186), uint8(187), uint8(162), uint8(76), uint8(246), uint8(56), uint8(191), uint8(168), uint8(10), uint8(220), uint8(18), uint8(72), uint8(195), uint8(169), uint8(119), uint8(221), uint8(75), uint8(188), uint8(45), uint8(226), uint8(254), uint8(66), uint8(162), uint8(120), uint8(125), uint8(45), uint8(231), uint8(6), uint8(165), uint8(223), uint8(106), uint8(93), uint8(232), uint8(201), uint8(127), uint8(3), uint8(34), uint8(98), uint8(134), uint8(203), uint8(63), uint8(231), uint8(120), uint8(84), uint8(90), uint8(137), uint8(231), uint8(131), uint8(73), uint8(50), uint8(23), uint8(11), uint8(22), uint8(64), uint8(173), uint8(8), uint8(180), uint8(31), uint8(245), uint8(132), uint8(154), uint8(195), uint8(208), uint8(236), uint8(120), uint8(88), uint8(248), uint8(233), uint8(98), uint8(186), uint8(90), uint8(69), uint8(242), uint8(125), uint8(207), uint8(208), uint8(66), uint8(18), uint8(130), uint8(243), uint8(96), uint8(245), uint8(159), uint8(15), uint8(120), uint8(113), uint8(128), uint8(184), uint8(74), uint8(83), uint8(107), uint8(188), uint8(255), uint8(137), uint8(69), uint8(46), uint8(120), uint8(9), uint8(127), uint8(165), uint8(242), uint8(248), uint8(75), uint8(139), uint8(225), uint8(83), uint8(129), uint8(8), uint8(36), uint8(77), uint8(4), uint8(145), uint8(163), uint8(58), uint8(92), uint8(207), uint8(3), uint8(7), uint8(28), uint8(133), uint8(184), uint8(149), uint8(209), uint8(96), uint8(220), uint8(215), uint8(239), uint8(36), uint8(191), uint8(143), uint8(161), uint8(61), uint8(247), uint8(245), uint8(137), uint8(8), uint8(133), uint8(120), uint8(48), uint8(68), uint8(203), uint8(151), uint8(250), uint8(8), uint8(129), uint8(222), uint8(63), uint8(192), uint8(70), uint8(90), uint8(107), uint8(188), uint8(255), uint8(203), uint8(248), uint8(156), uint8(34), uint8(23), uint8(8), uint8(135), uint8(6), uint8(64), uint8(5), uint8(249), uint8(214), uint8(195), uint8(65), uint8(183), uint8(183), uint8(104), uint8(62), uint8(108), uint8(93), uint8(81), uint8(244), uint8(92), uint8(226), uint8(161), uint8(119), uint8(248), uint8(4), uint8(167), uint8(159), uint8(15), uint8(159), uint8(192), uint8(20), uint8(21), uint8(233), uint8(49), uint8(201), uint8(132), uint8(32), uint8(140), uint8(114), uint8(43), uint8(113), uint8(51), uint8(152), uint8(227), uint8(224), uint8(142), uint8(189), uint8(159), uint8(4), uint8(139), uint8(182), uint8(123), uint8(9), uint8(97), uint8(0), uint8(74), uint8(112), uint8(85), uint8(92), uint8(152), uint8(247), uint8(242), uint8(97), uint8(32), uint8(116), uint8(117), uint8(112), uint8(140), uint8(32), uint8(30), uint8(224), uint8(192), uint8(89), uint8(144), uint8(120), uint8(102), uint8(101), uint8(202), uint8(129), uint8(199), uint8(30), uint8(77), uint8(206), uint8(16), uint8(81), uint8(152), uint8(52), uint8(166), uint8(7), uint8(4), uint8(98), uint8(229), uint8(252), uint8(56), uint8(227), uint8(69), uint8(128), uint8(19), uint8(190), uint8(247), uint8(63), uint8(189), uint8(82), uint8(8), uint8(3), uint8(8), uint8(32), uint8(52), uint8(185), uint8(102), uint8(170), uint8(171), uint8(123), uint8(132), uint8(32), uint8(241), uint8(129), uint8(10), uint8(213), uint8(247), uint8(32), uint8(35), uint8(181), uint8(220), uint8(60), uint8(59), uint8(105), uint8(77), uint8(221), uint8(231), uint8(250), uint8(97), uint8(8), uint8(70), uint8(190), uint8(145), uint8(224), uint8(196), uint8(35), uint8(128), uint8(0), uint8(0), uint8(1), uint8(220), uint8(65), uint8(154), uint8(84), uint8(27), uint8(252), uint8(110), uint8(164), uint8(254), uint8(50), uint8(166), uint8(14), uint8(177), uint8(185), uint8(62), uint8(197), uint8(81), uint8(75), uint8(77), uint8(234), uint8(248), uint8(59), uint8(177), uint8(50), uint8(0), uint8(29), uint8(203), uint8(170), uint8(92), uint8(135), uint8(192), uint8(247), uint8(167), uint8(145), uint8(133), uint8(183), uint8(111), uint8(229), uint8(19), uint8(218), uint8(220), uint8(132), uint8(191), uint8(99), uint8(130), uint8(243), uint8(211), uint8(225), uint8(141), uint8(247), uint8(155), uint8(157), uint8(239), uint8(165), uint8(65), uint8(254), uint8(11), uint8(187), uint8(218), uint8(255), uint8(13), uint8(240), uint8(223), uint8(167), uint8(147), uint8(248), uint8(79), uint8(229), uint8(250), uint8(47), uint8(226), uint8(120), uint8(92), uint8(34), uint8(28), uint8(34), uint8(128), uint8(11), uint8(243), uint8(172), uint8(195), uint8(97), uint8(181), uint8(27), uint8(176), uint8(0), uint8(231), uint8(70), uint8(136), uint8(106), uint8(137), uint8(171), uint8(210), uint8(77), uint8(139), uint8(170), uint8(23), uint8(69), uint8(206), uint8(1), uint8(4), uint8(203), uint8(128), uint8(38), uint8(107), uint8(209), uint8(223), uint8(215), uint8(196), uint8(96), uint8(0), uint8(59), uint8(255), uint8(205), uint8(55), uint8(233), uint8(210), uint8(123), uint8(136), uint8(154), uint8(244), uint8(52), uint8(152), uint8(0), uint8(151), uint8(77), uint8(15), uint8(53), uint8(211), uint8(189), uint8(190), uint8(252), uint8(2), uint8(90), uint8(49), uint8(87), uint8(154), uint8(162), uint8(224), uint8(255), uint8(5), uint8(158), uint8(36), uint8(0), uint8(71), uint8(109), uint8(14), uint8(117), uint8(189), uint8(61), uint8(254), uint8(133), uint8(43), uint8(202), uint8(185), uint8(141), uint8(184), uint8(214), uint8(254), uint8(141), uint8(123), uint8(228), uint8(239), uint8(107), uint8(4), uint8(78), uint8(89), uint8(210), uint8(8), uint8(133), uint8(142), uint8(249), uint8(154), uint8(239), uint8(248), uint8(127), uint8(135), uint8(221), uint8(127), uint8(75), uint8(22), uint8(164), uint8(11), uint8(141), uint8(252), uint8(3), uint8(16), uint8(75), uint8(29), uint8(249), uint8(21), uint8(229), uint8(210), uint8(10), uint8(179), uint8(216), uint8(27), uint8(220), uint8(255), uint8(59), uint8(169), uint8(101), uint8(146), uint8(105), uint8(47), uint8(87), uint8(22), uint8(196), uint8(123), uint8(214), uint8(230), uint8(3), uint8(150), uint8(181), uint8(32), uint8(38), uint8(158), uint8(254), uint8(244), uint8(162), uint8(112), uint8(254), uint8(235), uint8(234), uint8(186), uint8(79), uint8(220), uint8(37), uint8(225), uint8(16), uint8(168), uint8(182), uint8(115), uint8(102), uint8(15), uint8(89), uint8(131), uint8(1), uint8(70), uint8(89), uint8(210), uint8(13), uint8(151), uint8(124), uint8(103), uint8(189), uint8(98), uint8(186), uint8(47), uint8(35), uint8(175), uint8(51), uint8(10), uint8(240), uint8(233), uint8(238), uint8(60), uint8(176), uint8(29), uint8(89), uint8(80), uint8(172), uint8(140), uint8(14), uint8(116), uint8(4), uint8(191), uint8(155), uint8(13), uint8(6), uint8(27), uint8(157), uint8(126), uint8(254), uint8(4), uint8(185), uint8(215), uint8(236), uint8(84), uint8(53), uint8(35), uint8(82), uint8(252), uint8(191), uint8(229), uint8(240), uint8(69), uint8(252), uint8(42), uint8(92), uint8(4), uint8(194), uint8(70), uint8(85), uint8(106), uint8(45), uint8(89), uint8(131), uint8(73), uint8(178), uint8(127), uint8(1), uint8(102), uint8(47), uint8(144), uint8(118), uint8(62), uint8(102), uint8(175), uint8(231), uint8(196), uint8(221), uint8(216), uint8(255), uint8(175), uint8(56), uint8(68), uint8(51), uint8(47), uint8(254), uint8(71), uint8(254), uint8(1), uint8(159), uint8(63), uint8(170), uint8(28), uint8(31), uint8(232), uint8(21), uint8(18), uint8(9), uint8(195), uint8(131), uint8(32), uint8(2), uint8(39), uint8(167), uint8(169), uint8(247), uint8(191), uint8(208), uint8(68), uint8(109), uint8(180), uint8(154), uint8(220), uint8(239), uint8(190), uint8(126), uint8(234), uint8(93), uint8(242), uint8(47), uint8(143), uint8(143), uint8(62), uint8(212), uint8(187), uint8(228), uint8(38), uint8(207), uint8(143), uint8(19), uint8(194), uint8(16), uint8(184), uint8(75), uint8(207), uint8(13), uint8(24), uint8(248), uint8(248), uint8(11), uint8(0), uint8(151), uint8(5), uint8(106), uint8(125), uint8(237), uint8(143), uint8(189), uint8(124), uint8(190), uint8(16), uint8(234), uint8(38), uint8(21), uint8(18), uint8(170), uint8(6), uint8(221), uint8(197), uint8(105), uint8(150), uint8(15), uint8(7), uint8(132), uint8(145), uint8(55), uint8(142), uint8(132), uint8(90), uint8(110), uint8(132), uint8(167), uint8(231), uint8(67), uint8(139), uint8(5), uint8(108), uint8(158), uint8(207), uint8(172), uint8(193), uint8(8), uint8(68), uint8(18), uint8(85), uint8(116), uint8(202), uint8(95), uint8(195), uint8(88), uint8(68), uint8(176), uint8(174), uint8(29), uint8(247), uint8(203), uint8(18), uint8(197), uint8(197), uint8(136), uint8(41), uint8(199), uint8(3), uint8(179), uint8(187), uint8(103), uint8(0), uint8(12), uint8(94), uint8(238), uint8(211), uint8(116), uint8(33), uint8(71), uint8(162), uint8(105), uint8(90), uint8(15), uint8(180), uint8(95), uint8(4), uint8(1), uint8(144), uint8(66), uint8(17), uint8(130), uint8(104), uint8(38), uint8(71), uint8(74), uint8(151), uint8(17), uint8(208), uint8(129), uint8(193), uint8(121), uint8(108), uint8(46), uint8(220), uint8(147), uint8(183), uint8(61), uint8(64), uint8(0), uint8(0), uint8(1), uint8(159), uint8(65), uint8(154), uint8(96), uint8(223), uint8(225), uint8(254), uint8(121), uint8(75), uint8(58), uint8(220), uint8(38), uint8(255), uint8(215), uint8(6), uint8(124), uint8(0), uint8(78), uint8(105), uint8(121), uint8(244), uint8(96), uint8(191), uint8(235), uint8(94), uint8(142), uint8(21), uint8(111), uint8(50), uint8(240), uint8(96), uint8(64), uint8(255), uint8(206), uint8(239), uint8(102), uint8(110), uint8(151), uint8(240), uint8(222), uint8(222), uint8(124), uint8(201), uint8(80), uint8(127), uint8(227), uint8(214), uint8(183), uint8(180), uint8(190), uint8(23), uint8(39), uint8(0), uint8(6), uint8(156), uint8(66), uint8(93), uint8(149), uint8(115), uint8(250), uint8(72), uint8(190), uint8(98), uint8(215), uint8(95), uint8(209), uint8(185), uint8(184), uint8(92), uint8(78), uint8(0), uint8(113), uint8(199), uint8(165), uint8(192), uint8(205), uint8(58), uint8(225), uint8(133), uint8(128), uint8(155), uint8(124), uint8(191), uint8(23), uint8(192), uint8(204), uint8(41), uint8(98), uint8(247), uint8(101), uint8(218), uint8(183), uint8(0), uint8(40), uint8(205), uint8(23), uint8(99), uint8(250), uint8(254), uint8(79), uint8(91), uint8(198), uint8(215), uint8(26), uint8(76), uint8(48), uint8(3), uint8(23), uint8(239), uint8(171), uint8(238), uint8(218), uint8(189), uint8(224), uint8(105), uint8(91), uint8(47), uint8(198), uint8(252), uint8(217), uint8(35), uint8(174), uint8(188), uint8(245), uint8(160), uint8(190), uint8(237), uint8(47), uint8(27), uint8(44), uint8(159), uint8(217), uint8(67), uint8(177), uint8(106), uint8(122), uint8(190), uint8(255), uint8(154), uint8(35), uint8(230), uint8(50), uint8(189), uint8(123), uint8(103), uint8(5), uint8(48), uint8(138), uint8(251), uint8(140), uint8(214), uint8(239), uint8(131), uint8(125), uint8(128), uint8(242), uint8(179), uint8(28), uint8(31), uint8(239), uint8(136), uint8(164), uint8(33), uint8(105), uint8(117), uint8(227), uint8(247), uint8(151), uint8(202), uint8(117), uint8(172), uint8(118), uint8(183), uint8(172), uint8(13), uint8(181), uint8(99), uint8(121), uint8(52), uint8(216), uint8(9), uint8(254), uint8(111), uint8(147), uint8(242), uint8(243), uint8(220), uint8(20), uint8(141), uint8(243), uint8(3), uint8(9), uint8(244), uint8(19), uint8(123), uint8(239), uint8(201), uint8(63), uint8(124), uint8(158), uint8(17), uint8(4), uint8(34), uint8(196), uint8(122), uint8(146), uint8(114), uint8(29), uint8(89), uint8(192), uint8(118), uint8(181), uint8(242), uint8(248), uint8(46), uint8(242), uint8(225), uint8(168), uint8(158), uint8(98), uint8(56), uint8(32), uint8(61), uint8(1), uint8(250), uint8(38), uint8(129), uint8(96), uint8(244), uint8(27), uint8(151), uint8(192), uint8(192), uint8(115), uint8(133), uint8(175), uint8(151), uint8(193), uint8(135), uint8(225), uint8(16), uint8(86), uint8(47), uint8(4), uint8(109), uint8(36), uint8(189), uint8(238), uint8(247), uint8(115), uint8(43), uint8(95), uint8(133), uint8(255), uint8(146), uint8(47), uint8(181), uint8(164), uint8(255), uint8(0), uint8(11), uint8(231), uint8(93), uint8(223), uint8(219), uint8(131), uint8(252), uint8(159), uint8(215), uint8(227), uint8(66), uint8(33), uint8(192), uint8(132), uint8(1), uint8(10), uint8(215), uint8(61), uint8(15), uint8(237), uint8(130), uint8(150), uint8(20), uint8(46), uint8(246), uint8(10), uint8(237), uint8(253), uint8(133), uint8(171), uint8(127), uint8(224), uint8(3), uint8(32), uint8(171), uint8(231), uint8(148), uint8(63), uint8(224), uint8(1), uint8(183), uint8(167), uint8(214), uint8(72), uint8(242), uint8(159), uint8(8), uint8(118), uint8(208), uint8(32), uint8(132), uint8(73), uint8(147), uint8(215), uint8(2), uint8(135), uint8(8), uint8(240), uint8(201), uint8(143), uint8(143), uint8(128), uint8(177), uint8(22), uint8(160), uint8(118), uint8(109), uint8(121), uint8(210), uint8(141), uint8(53), uint8(242), uint8(248), uint8(91), uint8(8), uint8(112), uint8(136), uint8(100), uint8(74), uint8(168), uint8(2), uint8(22), uint8(144), uint8(34), uint8(156), uint8(106), uint8(212), uint8(210), uint8(76), uint8(52), uint8(51), uint8(230), uint8(9), uint8(109), uint8(132), uint8(183), uint8(129), uint8(41), uint8(154), uint8(200), uint8(255), uint8(83), uint8(255), uint8(128), uint8(202), uint8(99), uint8(147), uint8(43), uint8(250), uint8(223), uint8(254), uint8(179), uint8(4), uint8(20), uint8(20), uint8(107), uint8(85), uint8(93), uint8(50), uint8(172), uint8(24), uint8(112), uint8(175), uint8(54), uint8(47), uint8(224), uint8(210), uint8(76), uint8(128), uint8(192), uint8(98), uint8(1), uint8(153), uint8(129), uint8(212), uint8(57), uint8(104), uint8(251), uint8(172), uint8(95), uint8(13), uint8(139), uint8(126), uint8(164), uint8(206), uint8(191), uint8(94), uint8(17), uint8(239), uint8(253), uint8(120), uint8(67), uint8(123), uint8(162), uint8(29), uint8(48), uint8(0), uint8(0), uint8(1), uint8(135), uint8(65), uint8(154), uint8(128), uint8(223), uint8(225), uint8(254), uint8(25), uint8(123), uint8(217), uint8(77), uint8(156), uint8(9), uint8(174), uint8(217), uint8(218), uint8(87), uint8(205), uint8(9), uint8(109), uint8(52), uint8(84), uint8(7), uint8(31), uint8(20), uint8(32), uint8(2), uint8(239), uint8(249), uint8(210), uint8(12), uint8(252), uint8(107), uint8(73), uint8(159), uint8(122), uint8(56), uint8(245), uint8(183), uint8(31), uint8(248), uint8(94), uint8(31), uint8(158), uint8(177), uint8(215), uint8(8), uint8(133), uint8(250), uint8(126), uint8(223), uint8(127), uint8(4), uint8(126), uint8(251), uint8(202), uint8(215), uint8(0), uint8(10), uint8(252), uint8(56), uint8(72), uint8(0), uint8(58), uint8(99), uint8(202), uint8(196), uint8(147), uint8(185), uint8(118), uint8(189), uint8(230), uint8(154), uint8(65), uint8(36), uint8(52), uint8(149), uint8(202), uint8(63), uint8(252), uint8(6), uint8(120), uint8(4), uint8(120), uint8(0), uint8(215), uint8(229), uint8(87), uint8(191), uint8(62), uint8(224), uint8(7), uint8(239), uint8(114), uint8(149), uint8(235), uint8(111), uint8(13), uint8(147), uint8(93), uint8(38), uint8(156), uint8(24), uint8(88), uint8(167), uint8(95), uint8(239), uint8(128), uint8(98), uint8(165), uint8(226), uint8(150), uint8(209), uint8(95), uint8(206), uint8(124), uint8(124), uint8(172), uint8(199), uint8(7), uint8(250), uint8(248), uint8(140), uint8(174), uint8(90), uint8(212), uint8(18), uint8(209), uint8(5), uint8(77), uint8(224), uint8(230), uint8(156), uint8(96), uint8(59), uint8(209), uint8(123), uint8(111), uint8(48), uint8(62), uint8(176), uint8(85), uint8(102), uint8(178), uint8(1), uint8(76), uint8(169), uint8(237), uint8(190), uint8(190), uint8(17), uint8(12), uint8(137), uint8(103), uint8(241), uint8(122), uint8(233), uint8(252), uint8(187), uint8(79), uint8(227), uint8(184), uint8(252), uint8(190), uint8(35), uint8(160), uint8(142), uint8(27), uint8(62), uint8(95), uint8(127), uint8(234), uint8(111), uint8(47), uint8(130), uint8(239), uint8(146), uint8(21), uint8(35), uint8(87), uint8(181), uint8(17), uint8(193), uint8(60), uint8(3), uint8(12), uint8(96), uint8(114), uint8(210), uint8(96), uint8(14), uint8(142), uint8(76), uint8(164), uint8(124), uint8(191), uint8(1), uint8(164), uint8(227), uint8(120), uint8(39), uint8(203), uint8(225), uint8(14), uint8(112), uint8(140), uint8(34), uint8(81), uint8(165), uint8(199), uint8(119), uint8(175), uint8(195), uint8(38), uint8(159), uint8(254), uint8(255), uint8(0), uint8(33), uint8(31), uint8(239), uint8(175), uint8(251), uint8(248), uint8(127), uint8(147), uint8(211), uint8(241), uint8(60), uint8(76), uint8(56), uint8(42), uint8(0), uint8(100), uint8(2), uint8(191), uint8(160), uint8(47), uint8(20), uint8(238), uint8(148), uint8(62), uint8(210), uint8(99), uint8(35), uint8(129), uint8(246), uint8(195), uint8(130), uint8(101), uint8(133), uint8(61), uint8(126), uint8(0), uint8(31), uint8(101), uint8(177), uint8(146), uint8(217), uint8(186), uint8(127), uint8(175), uint8(192), uint8(5), uint8(231), uint8(33), uint8(22), uint8(111), uint8(226), uint8(239), uint8(170), uint8(225), uint8(0), uint8(134), uint8(150), uint8(225), uint8(24), uint8(84), uint8(67), uint8(190), uint8(243), uint8(224), uint8(52), uint8(134), uint8(200), uint8(36), uint8(153), uint8(5), uint8(52), uint8(99), uint8(179), uint8(64), uint8(26), uint8(156), uint8(56), uint8(200), uint8(119), uint8(251), uint8(95), uint8(154), uint8(192), uint8(13), uint8(152), uint8(177), uint8(246), uint8(79), uint8(181), uint8(250), uint8(194), uint8(1), uint8(0), uint8(128), uint8(68), uint8(24), uint8(9), uint8(207), uint8(225), uint8(176), uint8(81), uint8(191), uint8(144), uint8(223), uint8(255), uint8(197), uint8(47), uint8(211), uint8(173), uint8(4), uint8(20), uint8(17), uint8(241), uint8(172), uint8(73), uint8(80), uint8(218), uint8(172), uint8(24), uint8(4), uint8(18), uint8(10), uint8(241), uint8(60), uint8(95), uint8(192), uint8(225), uint8(5), uint8(57), uint8(144), uint8(129), uint8(68), uint8(16), uint8(18), uint8(144), uint8(160), uint8(210), uint8(28), uint8(185), uint8(208), uint8(185), uint8(4), uint8(127), uint8(246), uint8(190), uint8(83), uint8(5), uint8(198), uint8(35), uint8(152), uint8(38), uint8(158), uint8(72), uint8(132), uint8(55), uint8(107), uint8(245), uint8(225), uint8(29), uint8(47), uint8(250), uint8(132), uint8(54), uint8(185), uint8(100), uint8(8), uint8(132), uint8(219), uint8(205), uint8(254), uint8(218), uint8(11), uint8(29), uint8(48), uint8(0), uint8(0), uint8(1), uint8(168), uint8(65), uint8(154), uint8(160), uint8(222), uint8(171), uint8(195), uint8(16), uint8(53), uint8(109), uint8(37), uint8(19), uint8(170), uint8(6), uint8(190), uint8(224), uint8(176), uint8(152), uint8(112), uint8(128), uint8(76), uint8(217), uint8(67), uint8(70), uint8(250), uint8(4), uint8(21), uint8(89), uint8(97), uint8(19), uint8(71), uint8(48), uint8(33), uint8(181), uint8(107), uint8(192), uint8(127), uint8(57), uint8(100), uint8(219), uint8(174), uint8(122), uint8(28), uint8(78), uint8(24), uint8(33), uint8(172), uint8(196), uint8(112), uint8(254), uint8(27), uint8(243), uint8(118), uint8(112), uint8(174), uint8(191), uint8(255), uint8(193), uint8(54), uint8(71), uint8(253), uint8(110), uint8(219), uint8(120), uint8(152), uint8(96), uint8(150), uint8(231), uint8(234), uint8(0), uint8(29), uint8(40), uint8(140), uint8(235), uint8(234), uint8(241), uint8(112), uint8(87), uint8(127), uint8(128), uint8(36), uint8(58), uint8(172), uint8(153), uint8(63), uint8(124), uint8(189), uint8(243), uint8(165), uint8(211), uint8(59), uint8(212), uint8(192), uint8(68), uint8(195), uint8(158), uint8(0), uint8(1), uint8(246), uint8(155), uint8(81), uint8(162), uint8(131), uint8(221), uint8(216), uint8(30), uint8(221), uint8(192), uint8(8), uint8(107), uint8(73), uint8(211), uint8(119), uint8(239), uint8(231), uint8(182), uint8(241), uint8(81), uint8(166), uint8(1), uint8(6), uint8(146), uint8(143), uint8(7), uint8(252), uint8(0), uint8(115), uint8(181), uint8(29), uint8(169), uint8(102), uint8(129), uint8(176), uint8(147), uint8(235), uint8(174), uint8(250), uint8(252), uint8(8), uint8(125), uint8(182), uint8(0), uint8(170), uint8(35), uint8(173), uint8(175), uint8(122), uint8(254), uint8(183), uint8(52), uint8(80), uint8(237), uint8(196), uint8(113), uint8(174), uint8(183), uint8(117), uint8(83), uint8(158), uint8(153), uint8(2), uint8(204), uint8(151), uint8(251), uint8(251), uint8(33), uint8(250), uint8(70), uint8(52), uint8(69), uint8(222), uint8(176), uint8(166), uint8(50), uint8(53), uint8(129), uint8(140), uint8(197), uint8(101), uint8(160), uint8(53), uint8(92), uint8(59), uint8(87), uint8(105), uint8(58), uint8(241), uint8(233), uint8(192), uint8(1), uint8(221), uint8(223), uint8(159), uint8(189), uint8(155), uint8(13), uint8(131), uint8(86), uint8(81), uint8(68), uint8(25), uint8(40), uint8(210), uint8(168), uint8(116), uint8(92), uint8(191), uint8(136), uint8(194), uint8(40), uint8(34), uint8(9), uint8(133), uint8(206), uint8(78), uint8(178), uint8(185), uint8(226), uint8(242), uint8(188), uint8(68), uint8(42), uint8(124), uint8(75), uint8(155), uint8(191), uint8(19), uint8(175), uint8(71), uint8(31), uint8(229), uint8(240), uint8(93), uint8(241), uint8(97), uint8(16), uint8(247), uint8(49), uint8(18), uint8(199), uint8(19), uint8(197), uint8(115), uint8(17), uint8(197), uint8(104), uint8(21), uint8(66), uint8(216), uint8(17), uint8(22), uint8(78), uint8(215), uint8(224), uint8(21), uint8(180), uint8(107), uint8(163), uint8(242), uint8(255), uint8(194), uint8(48), uint8(152), uint8(43), uint8(23), uint8(203), uint8(143), uint8(110), uint8(238), uint8(231), uint8(165), uint8(182), uint8(79), uint8(174), uint8(32), uint8(78), uint8(17), uint8(116), uint8(71), uint8(221), uint8(10), uint8(184), uint8(92), uint8(33), uint8(252), uint8(0), uint8(41), uint8(126), uint8(83), uint8(229), uint8(233), uint8(127), uint8(253), uint8(189), uint8(81), uint8(177), uint8(43), uint8(12), uint8(67), uint8(245), uint8(240), uint8(16), uint8(66), uint8(238), uint8(208), uint8(67), uint8(122), uint8(128), uint8(116), uint8(98), uint8(53), uint8(102), uint8(191), uint8(50), uint8(35), uint8(231), uint8(255), uint8(212), uint8(2), uint8(226), uint8(181), uint8(91), uint8(244), uint8(255), uint8(190), uint8(174), uint8(16), uint8(8), uint8(104), uint8(191), uint8(133), uint8(2), uint8(1), uint8(28), uint8(34), uint8(21), uint8(17), uint8(184), uint8(45), uint8(125), uint8(138), uint8(63), uint8(72), uint8(0), uint8(64), uint8(238), uint8(192), uint8(8), uint8(217), uint8(190), uint8(38), uint8(223), uint8(124), uint8(12), uint8(78), uint8(186), uint8(118), uint8(135), uint8(248), uint8(0), uint8(200), uint8(189), uint8(41), uint8(181), uint8(126), uint8(248), uint8(25), uint8(119), uint8(109), uint8(53), uint8(143), uint8(250), uint8(208), uint8(67), uint8(5), uint8(2), uint8(220), uint8(67), uint8(157), uint8(222), uint8(218), uint8(208), uint8(64), uint8(208), uint8(74), uint8(89), uint8(51), uint8(166), uint8(211), uint8(73), uint8(21), uint8(96), uint8(186), uint8(120), uint8(100), uint8(70), uint8(108), uint8(129), uint8(181), uint8(192), uint8(149), uint8(78), uint8(176), uint8(63), uint8(255), uint8(175), uint8(8), uint8(233), uint8(127), uint8(240), uint8(65), uint8(244), uint8(32), uint8(104), uint8(118), uint8(79), uint8(216), uint8(75), uint8(140), uint8(203), uint8(255), uint8(208), uint8(225), uint8(109), uint8(128), uint8(0), uint8(0), uint8(1), uint8(179), uint8(65), uint8(154), uint8(192), uint8(223), uint8(225), uint8(184), uint8(25), uint8(111), uint8(183), uint8(250), uint8(9), uint8(134), uint8(226), uint8(65), uint8(50), uint8(204), uint8(178), uint8(7), uint8(192), uint8(44), uint8(230), uint8(221), uint8(243), uint8(9), uint8(184), uint8(200), uint8(208), uint8(106), uint8(62), uint8(27), uint8(128), uint8(155), uint8(95), uint8(30), uint8(249), uint8(107), uint8(110), uint8(216), uint8(13), uint8(112), uint8(151), uint8(181), uint8(126), uint8(180), uint8(223), uint8(145), uint8(253), uint8(31), uint8(45), uint8(186), uint8(240), uint8(65), uint8(224), uint8(0), uint8(203), uint8(217), uint8(17), uint8(185), uint8(54), uint8(201), uint8(19), uint8(151), uint8(147), uint8(125), uint8(236), uint8(161), uint8(169), uint8(20), uint8(67), uint8(4), uint8(63), uint8(93), uint8(184), uint8(74), uint8(38), uint8(34), uint8(134), uint8(0), uint8(66), uint8(247), uint8(221), uint8(110), uint8(240), uint8(236), uint8(228), uint8(136), uint8(226), uint8(46), uint8(221), uint8(219), uint8(242), uint8(26), uint8(151), uint8(72), uint8(74), uint8(92), uint8(126), uint8(3), uint8(206), uint8(155), uint8(19), uint8(221), uint8(143), uint8(122), uint8(79), uint8(164), uint8(205), uint8(23), uint8(241), uint8(162), uint8(58), uint8(95), uint8(22), uint8(141), uint8(27), uint8(127), uint8(95), uint8(104), uint8(51), uint8(229), uint8(55), uint8(203), uint8(25), uint8(133), uint8(189), uint8(104), uint8(238), uint8(139), uint8(210), uint8(238), uint8(90), uint8(11), uint8(59), uint8(151), uint8(75), uint8(121), uint8(155), uint8(97), uint8(233), uint8(134), uint8(35), uint8(223), uint8(239), uint8(4), uint8(51), uint8(35), uint8(172), uint8(21), uint8(52), uint8(109), uint8(172), uint8(217), uint8(104), uint8(50), uint8(55), uint8(195), uint8(177), uint8(187), uint8(224), uint8(223), uint8(128), uint8(113), uint8(29), uint8(206), uint8(15), uint8(247), uint8(196), uint8(180), uint8(34), uint8(144), uint8(104), uint8(64), uint8(154), uint8(54), uint8(144), uint8(211), uint8(37), uint8(111), uint8(192), uint8(107), uint8(62), uint8(19), uint8(91), uint8(238), uint8(203), uint8(178), uint8(233), uint8(217), uint8(96), uint8(54), uint8(108), uint8(91), uint8(169), uint8(23), uint8(172), uint8(127), uint8(202), uint8(174), uint8(152), uint8(111), uint8(180), uint8(222), uint8(250), uint8(190), uint8(17), uint8(26), uint8(37), uint8(98), uint8(14), uint8(86), uint8(32), uint8(144), uint8(30), uint8(211), uint8(224), uint8(240), uint8(221), uint8(151), uint8(147), uint8(80), uint8(78), uint8(146), uint8(212), uint8(156), uint8(37), uint8(59), uint8(210), uint8(2), uint8(187), uint8(175), uint8(246), uint8(66), uint8(227), uint8(97), uint8(247), uint8(151), uint8(94), uint8(188), uint8(66), uint8(12), uint8(149), uint8(4), uint8(125), uint8(233), uint8(93), uint8(192), uint8(218), uint8(58), uint8(220), uint8(105), uint8(84), uint8(162), uint8(142), uint8(126), uint8(130), uint8(90), uint8(87), uint8(229), uint8(240), uint8(109), uint8(229), uint8(18), uint8(17), uint8(13), uint8(231), uint8(143), uint8(220), uint8(17), uint8(251), uint8(219), uint8(194), uint8(47), uint8(15), uint8(125), uint8(126), uint8(81), uint8(239), uint8(119), uint8(248), uint8(100), uint8(68), uint8(30), uint8(253), uint8(208), uint8(0), uint8(255), uint8(129), uint8(9), uint8(201), uint8(163), uint8(70), uint8(120), uint8(63), uint8(201), uint8(233), uint8(248), uint8(159), uint8(97), uint8(192), uint8(132), uint8(0), uint8(217), uint8(44), uint8(237), uint8(43), uint8(165), uint8(111), uint8(16), uint8(68), uint8(99), uint8(85), uint8(32), uint8(17), uint8(0), uint8(255), uint8(240), uint8(2), uint8(105), uint8(249), uint8(165), uint8(95), uint8(158), uint8(255), uint8(128), uint8(18), uint8(181), uint8(17), uint8(207), uint8(255), uint8(42), uint8(225), uint8(0), uint8(132), uint8(152), uint8(119), uint8(223), uint8(137), uint8(32), uint8(100), uint8(172), uint8(197), uint8(248), uint8(1), uint8(240), uint8(193), uint8(128), uint8(255), uint8(47), uint8(129), uint8(4), uint8(140), uint8(32), uint8(62), uint8(16), uint8(8), uint8(134), uint8(77), uint8(169), uint8(176), uint8(41), uint8(17), uint8(112), uint8(180), uint8(222), uint8(31), uint8(253), uint8(100), uint8(8), uint8(96), uint8(160), uint8(162), uint8(183), uint8(119), uint8(63), uint8(63), uint8(45), uint8(191), uint8(154), uint8(101), uint8(47), uint8(142), uint8(230), uint8(225), uint8(146), uint8(147), uint8(21), uint8(223), uint8(47), uint8(133), uint8(47), uint8(87), uint8(30), uint8(245), uint8(131), uint8(9), uint8(194), uint8(40), uint8(197), uint8(77), uint8(120), uint8(71), uint8(75), uint8(254), uint8(240), uint8(208), uint8(118), uint8(3), uint8(169), uint8(174), uint8(237), uint8(248), uint8(0), uint8(135), uint8(238), uint8(231), uint8(89), uint8(249), uint8(124), uint8(225), uint8(19), uint8(125), uint8(4), uint8(146), uint8(42), uint8(198), uint8(112), uint8(208), uint8(169), uint8(188), uint8(222), uint8(181), uint8(135), uint8(240), uint8(15), uint8(128), uint8(0), uint8(0), uint8(1), uint8(30), uint8(65), uint8(154), uint8(224), uint8(71), uint8(248), uint8(111), uint8(128), uint8(160), uint8(189), uint8(170), uint8(74), uint8(114), uint8(155), uint8(156), uint8(116), uint8(57), uint8(14), uint8(55), uint8(252), uint8(55), uint8(88), uint8(113), uint8(237), uint8(112), uint8(32), uint8(255), uint8(110), uint8(231), uint8(255), uint8(4), uint8(111), uint8(143), uint8(59), uint8(144), uint8(159), uint8(118), uint8(34), uint8(39), uint8(225), uint8(99), uint8(96), uint8(1), uint8(118), uint8(251), uint8(171), uint8(254), uint8(254), uint8(239), uint8(240), uint8(1), uint8(127), uint8(25), uint8(20), uint8(125), uint8(251), uint8(122), uint8(6), uint8(164), uint8(107), uint8(220), uint8(236), uint8(171), uint8(238), uint8(142), uint8(174), uint8(18), uint8(61), uint8(119), uint8(172), uint8(243), uint8(9), uint8(96), uint8(140), uint8(250), uint8(254), uint8(79), uint8(47), uint8(227), uint8(176), uint8(138), uint8(133), uint8(68), uint8(233), uint8(249), uint8(193), uint8(160), uint8(74), uint8(203), uint8(130), uint8(150), uint8(10), uint8(93), uint8(128), uint8(228), uint8(232), uint8(198), uint8(189), uint8(243), uint8(124), uint8(239), uint8(8), uint8(42), uint8(199), uint8(86), uint8(117), uint8(255), uint8(12), uint8(209), uint8(148), uint8(14), uint8(149), uint8(238), uint8(22), uint8(73), uint8(219), uint8(246), uint8(222), uint8(245), uint8(145), uint8(31), uint8(243), uint8(59), uint8(212), uint8(181), uint8(255), uint8(151), uint8(253), uint8(132), uint8(225), uint8(16), uint8(80), uint8(115), uint8(17), uint8(93), uint8(109), uint8(107), uint8(95), uint8(130), uint8(0), uint8(138), uint8(61), uint8(203), uint8(232), uint8(174), uint8(250), uint8(59), uint8(252), uint8(103), uint8(180), uint8(79), uint8(107), uint8(252), uint8(34), uint8(8), uint8(122), uint8(195), uint8(65), uint8(192), uint8(105), uint8(38), uint8(72), uint8(64), uint8(247), uint8(192), uint8(2), uint8(98), uint8(93), uint8(240), uint8(84), uint8(97), uint8(254), uint8(72), uint8(100), uint8(167), uint8(243), uint8(83), uint8(137), uint8(23), uint8(173), uint8(107), uint8(62), uint8(95), uint8(132), uint8(5), uint8(4), uint8(6), uint8(20), uint8(88), uint8(68), uint8(54), uint8(104), uint8(6), uint8(188), uint8(140), uint8(46), uint8(101), uint8(184), uint8(0), uint8(115), uint8(180), uint8(213), uint8(223), uint8(110), uint8(252), uint8(0), uint8(100), uint8(178), uint8(220), uint8(209), uint8(45), uint8(255), uint8(187), uint8(151), uint8(197), uint8(4), uint8(56), uint8(68), uint8(208), uint8(70), uint8(113), uint8(88), uint8(172), uint8(119), uint8(5), uint8(188), uint8(128), uint8(198), uint8(95), uint8(21), uint8(127), uint8(10), uint8(205), uint8(154), uint8(90), uint8(170), uint8(69), uint8(227), uint8(173), uint8(87), uint8(119), uint8(215), uint8(156), uint8(34), uint8(9), uint8(13), uint8(195), uint8(126), uint8(139), uint8(175), uint8(175), uint8(175), uint8(107), uint8(156), uint8(34), uint8(26), uint8(9), uint8(159), uint8(13), uint8(244), uint8(5), uint8(192), uint8(143), uint8(85), uint8(95), uint8(136), uint8(239), uint8(240), uint8(168), uint8(133), uint8(90), uint8(75), uint8(89), uint8(208), uint8(148), uint8(191), uint8(142), uint8(172), uint8(255), uint8(130), uint8(113), uint8(78), uint8(239), uint8(89), uint8(190), uint8(59), uint8(152), uint8(0), uint8(0), uint8(1), uint8(196), uint8(65), uint8(155), uint8(0), uint8(71), uint8(248), uint8(111), uint8(128), uint8(180), uint8(153), uint8(213), uint8(98), uint8(198), uint8(101), uint8(141), uint8(96), uint8(5), uint8(29), uint8(127), uint8(39), uint8(195), uint8(214), uint8(27), uint8(248), uint8(201), uint8(195), uint8(96), uint8(248), uint8(111), uint8(134), uint8(60), uint8(133), uint8(229), uint8(204), uint8(162), uint8(154), uint8(77), uint8(15), uint8(157), uint8(248), uint8(12), uint8(70), uint8(229), uint8(249), uint8(236), uint8(191), uint8(139), uint8(248), uint8(92), uint8(156), uint8(0), uint8(62), uint8(91), uint8(250), uint8(186), uint8(223), uint8(187), uint8(232), uint8(198), uint8(115), uint8(33), uint8(162), uint8(118), uint8(173), uint8(232), uint8(136), uint8(67), uint8(86), uint8(160), uint8(17), uint8(10), uint8(218), uint8(224), uint8(7), uint8(151), uint8(237), uint8(42), uint8(170), uint8(220), uint8(0), uint8(160), uint8(170), uint8(139), uint8(155), uint8(87), uint8(242), uint8(122), uint8(118), uint8(42), uint8(187), uint8(141), uint8(38), uint8(30), uint8(89), uint8(233), uint8(38), uint8(109), uint8(77), uint8(248), uint8(33), uint8(252), uint8(254), uint8(170), uint8(7), uint8(0), uint8(16), uint8(107), uint8(235), uint8(245), uint8(115), uint8(254), uint8(227), uint8(83), uint8(70), uint8(14), uint8(186), uint8(251), uint8(251), uint8(240), uint8(70), uint8(41), uint8(10), uint8(163), uint8(221), uint8(215), uint8(213), uint8(123), uint8(150), uint8(127), uint8(2), uint8(154), uint8(30), uint8(156), uint8(253), uint8(24), uint8(0), uint8(215), uint8(252), uint8(85), uint8(228), uint8(254), uint8(176), uint8(65), uint8(133), uint8(68), uint8(67), uint8(162), uint8(118), uint8(208), uint8(49), uint8(156), uint8(140), uint8(255), uint8(128), uint8(246), uint8(190), uint8(103), uint8(86), uint8(121), uint8(11), uint8(204), uint8(14), uint8(90), uint8(140), uint8(49), uint8(149), uint8(175), uint8(26), uint8(151), uint8(142), uint8(255), uint8(215), uint8(210), uint8(205), uint8(175), uint8(147), uint8(245), uint8(8), uint8(255), uint8(12), uint8(252), uint8(160), uint8(134), uint8(201), uint8(56), uint8(60), uint8(21), uint8(36), uint8(197), uint8(69), uint8(106), uint8(249), uint8(95), uint8(175), uint8(249), uint8(235), uint8(71), uint8(235), uint8(225), uint8(16), uint8(192), uint8(209), uint8(165), uint8(158), uint8(179), uint8(17), uint8(39), uint8(108), uint8(165), uint8(129), uint8(23), uint8(207), uint8(172), uint8(178), uint8(184), uint8(143), uint8(175), uint8(198), uint8(135), uint8(67), uint8(197), uint8(202), uint8(113), uint8(177), uint8(91), uint8(169), uint8(67), uint8(41), uint8(144), uint8(156), uint8(207), uint8(106), uint8(45), uint8(127), uint8(92), uint8(173), uint8(2), uint8(207), uint8(24), uint8(30), uint8(15), uint8(236), uint8(57), uint8(38), uint8(87), uint8(127), uint8(27), uint8(249), uint8(38), uint8(64), uint8(156), uint8(62), uint8(99), uint8(154), uint8(104), uint8(75), uint8(30), uint8(47), uint8(58), uint8(240), uint8(248), uint8(134), uint8(203), uint8(36), uint8(5), uint8(93), uint8(226), uint8(58), uint8(185), uint8(172), uint8(50), uint8(30), uint8(75), uint8(239), uint8(253), uint8(0), uint8(193), uint8(234), uint8(127), uint8(236), uint8(15), uint8(255), uint8(244), uint8(144), uint8(142), uint8(28), uint8(25), uint8(0), uint8(11), uint8(233), uint8(154), uint8(190), uint8(166), uint8(219), uint8(235), uint8(90), uint8(46), uint8(171), uint8(67), uint8(217), uint8(41), uint8(136), uint8(93), uint8(81), uint8(67), uint8(110), uint8(171), uint8(133), uint8(2), uint8(48), uint8(175), uint8(6), uint8(211), uint8(46), uint8(80), uint8(73), uint8(146), uint8(99), uint8(218), uint8(95), uint8(29), uint8(0), uint8(67), uint8(241), uint8(191), uint8(159), uint8(191), uint8(240), uint8(207), uint8(179), uint8(1), uint8(210), uint8(196), uint8(0), uint8(248), uint8(8), uint8(134), uint8(159), uint8(117), uint8(47), uint8(252), uint8(190), uint8(40), uint8(33), uint8(8), uint8(4), uint8(10), uint8(44), uint8(34), uint8(24), uint8(33), uint8(239), uint8(0), uint8(79), uint8(213), uint8(174), uint8(181), uint8(125), uint8(208), uint8(22), uint8(242), uint8(248), uint8(0), uint8(62), uint8(169), uint8(180), uint8(190), uint8(95), uint8(135), uint8(128), uint8(5), uint8(207), uint8(210), uint8(250), uint8(106), uint8(79), uint8(254), uint8(250), uint8(200), uint8(16), uint8(52), uint8(18), uint8(156), uint8(52), uint8(243), uint8(243), uint8(221), uint8(189), uint8(155), uint8(212), uint8(240), uint8(175), uint8(38), uint8(3), uint8(137), uint8(102), uint8(108), uint8(241), uint8(66), uint8(188), uint8(213), uint8(0), uint8(136), uint8(106), uint8(125), uint8(210), uint8(215), uint8(127), uint8(75), uint8(194), uint8(40), uint8(197), uint8(23), uint8(125), uint8(60), uint8(33), uint8(63), uint8(207), uint8(10), uint8(139), uint8(159), uint8(49), uint8(42), uint8(133), uint8(233), uint8(196), uint8(154), uint8(74), uint8(127), uint8(91), uint8(8), uint8(194), uint8(193), uint8(158), uint8(26), uint8(73), uint8(76), uint8(246), uint8(176), uint8(133), uint8(185), uint8(255), uint8(11), uint8(138), uint8(173), uint8(93), uint8(98), uint8(124), uint8(22), uint8(169), uint8(252), uint8(94), uint8(176), uint8(0), uint8(0), uint8(1), uint8(178), uint8(65), uint8(155), uint8(32), uint8(87), uint8(87), uint8(134), uint8(235), uint8(12), uint8(123), uint8(238), uint8(2), uint8(22), uint8(166), uint8(215), uint8(251), uint8(39), uint8(223), uint8(248), uint8(68), uint8(16), uint8(135), uint8(49), uint8(112), uint8(3), uint8(20), uint8(209), uint8(13), uint8(89), uint8(53), uint8(123), uint8(192), uint8(68), uint8(37), uint8(39), uint8(192), uint8(35), uint8(220), uint8(180), uint8(95), uint8(239), uint8(128), uint8(1), uint8(255), uint8(92), uint8(168), uint8(225), uint8(39), uint8(170), uint8(106), uint8(63), uint8(110), uint8(52), uint8(152), uint8(1), uint8(247), uint8(20), uint8(105), uint8(164), uint8(189), uint8(140), uint8(127), uint8(233), uint8(199), uint8(14), uint8(111), uint8(196), uint8(40), uint8(80), uint8(122), uint8(65), uint8(26), uint8(212), uint8(7), uint8(159), uint8(147), uint8(99), uint8(124), uint8(236), uint8(204), uint8(191), uint8(140), uint8(189), uint8(231), uint8(140), uint8(165), uint8(5), uint8(148), uint8(23), uint8(239), uint8(33), uint8(86), uint8(204), uint8(103), uint8(122), uint8(246), uint8(206), uint8(10), uint8(97), uint8(21), uint8(247), uint8(25), uint8(173), uint8(223), uint8(6), uint8(251), uint8(1), uint8(229), uint8(102), uint8(56), uint8(63), uint8(223), uint8(13), uint8(52), uint8(132), uint8(232), uint8(4), uint8(47), uint8(119), uint8(187), uint8(135), uint8(51), uint8(235), uint8(51), uint8(27), uint8(94), uint8(248), uint8(54), uint8(213), uint8(141), uint8(228), uint8(211), uint8(96), uint8(4), uint8(127), uint8(157), uint8(82), uint8(15), uint8(57), uint8(59), uint8(226), uint8(19), uint8(79), uint8(224), uint8(75), uint8(122), uint8(9), uint8(191), uint8(187), uint8(223), uint8(124), uint8(58), uint8(112), uint8(32), uint8(5), uint8(230), uint8(134), uint8(69), uint8(207), uint8(57), uint8(156), uint8(24), uint8(11), uint8(178), uint8(28), uint8(23), uint8(130), uint8(197), uint8(228), uint8(16), uint8(63), uint8(147), uint8(0), uint8(35), uint8(103), uint8(205), uint8(26), uint8(111), uint8(247), uint8(194), uint8(151), uint8(168), uint8(72), uint8(207), uint8(117), uint8(106), uint8(254), uint8(79), uint8(92), uint8(16), uint8(255), uint8(12), uint8(248), uint8(160), uint8(0), uint8(70), uint8(40), uint8(0), uint8(48), uint8(130), uint8(204), uint8(65), uint8(67), uint8(18), uint8(3), uint8(51), uint8(255), uint8(201), uint8(235), uint8(146), uint8(19), uint8(160), uint8(136), uint8(68), uint8(62), uint8(22), uint8(8), uint8(227), uint8(213), uint8(74), uint8(124), uint8(103), uint8(252), uint8(254), uint8(9), uint8(94), uint8(94), uint8(125), uint8(181), uint8(85), uint8(10), uint8(135), uint8(2), uint8(80), uint8(0), uint8(111), uint8(232), uint8(98), uint8(42), uint8(46), uint8(213), uint8(63), uint8(17), uint8(212), uint8(202), uint8(140), uint8(214), uint8(102), uint8(38), uint8(175), uint8(255), uint8(47), uint8(252), uint8(1), uint8(50), uint8(157), uint8(180), uint8(248), uint8(254), uint8(255), uint8(224), uint8(2), uint8(89), uint8(167), uint8(73), uint8(245), uint8(223), uint8(233), uint8(127), uint8(25), uint8(194), uint8(48), uint8(169), uint8(0), uint8(122), uint8(133), uint8(199), uint8(243), uint8(248), uint8(60), uint8(176), uint8(2), uint8(110), uint8(155), uint8(21), uint8(60), uint8(1), uint8(8), uint8(189), uint8(182), uint8(26), uint8(227), uint8(246), uint8(195), uint8(141), uint8(55), uint8(173), uint8(112), uint8(200), uint8(190), uint8(10), uint8(28), uint8(52), uint8(179), uint8(206), uint8(33), uint8(101), uint8(24), uint8(159), uint8(4), uint8(34), uint8(63), uint8(0), uint8(217), uint8(101), uint8(141), uint8(138), uint8(223), uint8(107), uint8(255), uint8(92), uint8(32), uint8(22), uint8(8), uint8(130), uint8(241), uint8(82), uint8(101), uint8(194), uint8(17), uint8(127), uint8(222), uint8(3), uint8(98), uint8(230), uint8(101), uint8(30), uint8(178), uint8(147), uint8(145), uint8(74), uint8(112), uint8(20), uint8(238), uint8(176), uint8(0), uint8(109), uint8(156), uint8(86), uint8(82), uint8(255), uint8(15), uint8(4), uint8(123), uint8(216), uint8(0), uint8(199), uint8(34), uint8(22), uint8(70), uint8(187), uint8(190), uint8(31), uint8(52), uint8(42), uint8(81), uint8(44), uint8(31), uint8(203), uint8(226), uint8(31), uint8(18), uint8(15), uint8(227), uint8(19), uint8(135), uint8(47), uint8(130), uint8(107), uint8(148), uint8(34), uint8(224), uint8(146), uint8(170), uint8(182), uint8(240), uint8(97), uint8(57), uint8(12), uint8(159), uint8(135), uint8(116), uint8(87), uint8(254), uint8(255), uint8(240), uint8(135), uint8(120), uint8(66), uint8(112), uint8(137), uint8(202), uint8(190), uint8(25), uint8(181), uint8(127), uint8(249), uint8(124), uint8(225), uint8(18), uint8(124), uint8(18), uint8(148), uint8(60), uint8(41), uint8(23), uint8(206), uint8(191), uint8(137), uint8(21), uint8(100), uint8(210), uint8(225), uint8(172), uint8(20), uint8(236), uint8(46), uint8(33), uint8(239), uint8(171), uint8(169), uint8(83), uint8(249), uint8(161), uint8(88), uint8(0), uint8(0), uint8(1), uint8(251), uint8(65), uint8(155), uint8(64), uint8(103), uint8(41), uint8(63), uint8(173), uint8(252), uint8(47), uint8(224), uint8(7), uint8(169), uint8(234), uint8(189), uint8(63), uint8(135), uint8(1), uint8(61), uint8(38), uint8(213), uint8(245), uint8(55), uint8(25), uint8(2), uint8(175), uint8(14), uint8(195), uint8(253), uint8(224), uint8(9), uint8(95), uint8(250), uint8(113), uint8(57), uint8(39), uint8(182), uint8(154), uint8(254), uint8(22), uint8(38), uint8(4), uint8(229), uint8(71), uint8(53), uint8(228), uint8(235), uint8(251), uint8(189), uint8(100), uint8(23), uint8(102), uint8(46), uint8(144), uint8(120), uint8(12), uint8(116), uint8(29), uint8(132), uint8(17), uint8(187), uint8(189), uint8(106), uint8(23), uint8(32), uint8(5), uint8(13), uint8(220), uint8(175), uint8(8), uint8(102), uint8(241), uint8(47), uint8(235), uint8(255), uint8(223), uint8(121), uint8(235), uint8(130), uint8(53), uint8(61), uint8(64), uint8(211), uint8(35), uint8(127), uint8(247), uint8(223), uint8(47), uint8(224), uint8(219), uint8(194), uint8(33), uint8(99), uint8(128), uint8(158), uint8(145), uint8(157), uint8(106), uint8(243), uint8(233), uint8(73), uint8(148), uint8(19), uint8(101), uint8(167), uint8(217), uint8(225), uint8(1), uint8(86), uint8(112), uint8(145), uint8(116), uint8(45), uint8(140), uint8(92), uint8(188), uint8(56), uint8(194), uint8(223), uint8(250), uint8(93), uint8(126), uint8(25), uint8(131), uint8(105), uint8(144), uint8(245), uint8(156), uint8(7), uint8(64), uint8(116), uint8(58), uint8(99), uint8(151), uint8(240), uint8(106), uint8(28), uint8(190), uint8(45), uint8(224), uint8(64), uint8(227), uint8(65), uint8(56), uint8(31), uint8(166), uint8(82), uint8(95), uint8(3), uint8(244), uint8(202), uint8(75), uint8(225), uint8(147), uint8(145), uint8(220), uint8(201), uint8(197), uint8(223), uint8(208), uint8(156), uint8(142), uint8(230), uint8(78), uint8(46), uint8(254), uint8(54), uint8(135), uint8(192), uint8(16), uint8(147), uint8(83), uint8(213), uint8(127), uint8(176), uint8(244), uint8(154), uint8(158), uint8(171), uint8(253), uint8(165), uint8(28), uint8(135), uint8(106), uint8(82), uint8(142), uint8(67), uint8(181), uint8(32), uint8(23), uint8(21), uint8(201), uint8(253), uint8(50), uint8(113), uint8(92), uint8(159), uint8(211), uint8(50), uint8(223), uint8(187), uint8(226), uint8(59), uint8(126), uint8(239), uint8(134), uint8(168), uint8(78), uint8(134), uint8(130), uint8(143), uint8(192), uint8(8), uint8(143), uint8(194), uint8(142), uint8(236), uint8(126), uint8(108), uint8(49), uint8(90), uint8(70), uint8(200), uint8(181), uint8(123), uint8(225), uint8(85), uint8(25), uint8(164), uint8(64), uint8(198), uint8(92), uint8(232), uint8(62), uint8(217), uint8(26), uint8(70), uint8(12), uint8(101), uint8(206), uint8(48), uint8(132), uint8(98), uint8(38), uint8(0), uint8(26), uint8(156), uint8(26), uint8(246), uint8(219), uint8(201), uint8(184), uint8(31), uint8(108), uint8(137), uint8(35), uint8(4), uint8(34), uint8(231), uint8(80), uint8(204), uint8(189), uint8(106), uint8(126), uint8(253), uint8(194), uint8(16), uint8(208), uint8(128), uint8(145), uint8(1), uint8(69), uint8(234), uint8(183), uint8(209), uint8(87), uint8(71), uint8(84), uint8(130), uint8(194), uint8(245), uint8(24), uint8(241), uint8(240), uint8(239), uint8(164), uint8(17), uint8(175), uint8(226), uint8(182), uint8(233), uint8(175), uint8(220), uint8(228), uint8(156), uint8(160), uint8(253), uint8(64), uint8(198), uint8(110), uint8(112), uint8(86), uint8(55), uint8(223), uint8(210), uint8(254), uint8(12), uint8(130), uint8(24), uint8(70), uint8(30), uint8(134), uint8(166), uint8(68), uint8(107), uint8(228), uint8(30), uint8(177), uint8(85), uint8(25), uint8(226), uint8(137), uint8(50), uint8(192), uint8(93), uint8(52), uint8(25), uint8(142), uint8(106), uint8(213), uint8(241), uint8(22), uint8(131), uint8(5), uint8(59), uint8(13), uint8(225), uint8(127), uint8(128), uint8(8), uint8(141), uint8(221), uint8(175), uint8(128), uint8(140), uint8(85), uint8(118), uint8(86), uint8(114), uint8(252), uint8(0), uint8(40), uint8(181), uint8(145), uint8(204), uint8(153), uint8(151), uint8(6), uint8(124), uint8(190), uint8(110), uint8(18), uint8(8), uint8(216), uint8(47), uint8(196), uint8(39), uint8(137), uint8(222), uint8(238), uint8(31), uint8(48), uint8(15), uint8(210), uint8(93), uint8(192), uint8(241), uint8(121), uint8(192), uint8(159), uint8(203), uint8(201), uint8(114), uint8(190), uint8(159), uint8(175), uint8(112), uint8(85), uint8(27), uint8(91), uint8(183), uint8(203), uint8(137), uint8(67), uint8(79), uint8(123), uint8(50), uint8(249), uint8(34), uint8(236), uint8(34), uint8(231), uint8(233), uint8(151), uint8(241), uint8(123), uint8(176), uint8(117), uint8(7), uint8(12), uint8(57), uint8(192), uint8(64), uint8(143), uint8(182), uint8(173), uint8(90), uint8(196), uint8(47), uint8(193), uint8(41), uint8(63), uint8(224), uint8(4), uint8(94), uint8(186), uint8(61), uint8(62), uint8(251), uint8(248), uint8(0), uint8(81), uint8(50), uint8(26), uint8(35), uint8(147), uint8(185), uint8(28), uint8(143), uint8(194), uint8(58), uint8(120), uint8(46), uint8(148), uint8(120), uint8(34), uint8(196), uint8(57), uint8(225), uint8(238), uint8(21), uint8(43), uint8(138), uint8(231), uint8(199), uint8(191), uint8(168), uint8(1), uint8(34), uint8(54), uint8(175), uint8(242), uint8(249), uint8(42), uint8(94), uint8(190), uint8(201), uint8(239), uint8(96), uint8(150), uint8(10), uint8(230), uint8(8), uint8(140), uint8(97), uint8(114), uint8(123), uint8(115), uint8(113), uint8(15), uint8(63), uint8(192), uint8(27), uint8(197), uint8(216), uint8(175), uint8(68), uint8(138), uint8(178), uint8(89), uint8(135), uint8(211), uint8(1), uint8(45), uint8(204), uint8(175), uint8(238), uint8(225), uint8(192), uint8(1), uint8(243), uint8(70), uint8(37), uint8(236), uint8(92), uint8(133), uint8(202), uint8(36), uint8(0), uint8(0), uint8(1), uint8(193), uint8(65), uint8(155), uint8(96), uint8(33), uint8(203), uint8(225), uint8(204), uint8(1), uint8(144), uint8(100), uint8(201), uint8(190), uint8(212), uint8(40), uint8(180), uint8(154), uint8(96), uint8(197), uint8(237), uint8(0), uint8(112), uint8(17), uint8(224), uint8(6), uint8(108), uint8(157), uint8(249), uint8(206), uint8(0), uint8(59), uint8(47), uint8(205), uint8(114), uint8(222), uint8(253), uint8(118), uint8(234), uint8(55), uint8(154), uint8(32), uint8(0), uint8(217), uint8(122), uint8(49), uint8(248), uint8(141), uint8(162), uint8(252), uint8(251), uint8(155), uint8(112), uint8(69), uint8(238), uint8(157), uint8(244), uint8(110), uint8(204), uint8(54), uint8(91), uint8(109), uint8(98), uint8(103), uint8(105), uint8(149), uint8(101), uint8(24), uint8(245), uint8(201), uint8(95), uint8(238), uint8(176), uint8(155), uint8(101), uint8(98), uint8(179), uint8(22), uint8(75), uint8(185), uint8(233), uint8(144), uint8(40), uint8(201), uint8(239), uint8(239), uint8(236), uint8(135), uint8(121), uint8(16), uint8(106), uint8(171), uint8(235), uint8(175), uint8(20), uint8(176), uint8(158), uint8(130), uint8(110), uint8(252), uint8(255), uint8(142), uint8(231), uint8(52), uint8(59), uint8(217), uint8(193), uint8(72), uint8(22), uint8(113), uint8(103), uint8(252), uint8(195), uint8(107), uint8(209), uint8(206), uint8(168), uint8(111), uint8(122), uint8(248), uint8(68), uint8(16), uint8(240), uint8(20), uint8(23), uint8(156), uint8(200), uint8(123), uint8(200), uint8(144), uint8(214), uint8(225), uint8(24), uint8(116), uint8(72), uint8(58), uint8(88), uint8(14), uint8(172), uint8(7), uint8(175), uint8(224), uint8(196), uint8(208), uint8(96), uint8(218), uint8(65), uint8(219), uint8(132), uint8(15), uint8(117), uint8(7), uint8(5), uint8(192), uint8(3), uint8(96), uint8(203), uint8(242), uint8(95), uint8(73), uint8(183), uint8(54), uint8(185), uint8(237), uint8(255), uint8(128), uint8(37), uint8(55), uint8(164), uint8(125), uint8(125), uint8(26), uint8(251), uint8(60), uint8(98), uint8(29), uint8(182), uint8(205), uint8(60), uint8(27), uint8(126), uint8(62), uint8(240), uint8(247), uint8(191), uint8(80), uint8(185), uint8(191), uint8(0), uint8(11), uint8(212), uint8(153), uint8(158), uint8(74), uint8(190), uint8(161), uint8(63), uint8(72), uint8(208), uint8(64), uint8(191), uint8(191), uint8(80), uint8(52), uint8(177), uint8(110), uint8(221), uint8(133), uint8(173), uint8(125), uint8(216), uint8(3), uint8(129), uint8(95), uint8(213), uint8(2), uint8(184), uint8(2), uint8(93), uint8(87), uint8(48), uint8(143), uint8(63), uint8(255), uint8(244), uint8(7), uint8(229), uint8(5), uint8(112), uint8(5), uint8(233), uint8(61), uint8(205), uint8(3), uint8(38), uint8(191), uint8(253), uint8(201), uint8(250), uint8(194), uint8(8), uint8(33), uint8(194), uint8(33), uint8(157), uint8(64), uint8(58), uint8(193), uint8(83), uint8(22), uint8(64), uint8(57), uint8(0), uint8(232), uint8(105), uint8(2), uint8(125), uint8(132), uint8(182), uint8(192), uint8(34), uint8(25), uint8(108), uint8(175), uint8(252), uint8(254), uint8(28), uint8(1), uint8(150), uint8(229), uint8(177), uint8(95), uint8(254), uint8(127), uint8(15), uint8(194), uint8(16), uint8(220), uint8(14), uint8(132), uint8(68), uint8(25), uint8(223), uint8(10), uint8(152), uint8(194), uint8(167), uint8(224), uint8(113), uint8(12), uint8(91), uint8(159), uint8(192), uint8(26), uint8(216), uint8(246), uint8(47), uint8(61), uint8(245), uint8(226), uint8(225), uint8(89), uint8(49), uint8(117), uint8(193), uint8(246), uint8(3), uint8(45), uint8(9), uint8(144), uint8(149), uint8(40), uint8(28), uint8(228), uint8(215), uint8(134), uint8(12), uint8(237), uint8(107), uint8(95), uint8(147), uint8(223), uint8(6), uint8(159), uint8(56), uint8(68), uint8(51), uint8(120), uint8(85), uint8(209), uint8(41), uint8(218), uint8(253), uint8(171), uint8(99), uint8(93), uint8(95), uint8(130), uint8(141), uint8(86), uint8(181), uint8(246), uint8(95), uint8(240), uint8(97), uint8(132), uint8(14), uint8(76), uint8(63), uint8(4), uint8(223), uint8(217), uint8(255), uint8(84), uint8(120), uint8(84), uint8(224), uint8(245), uint8(224), uint8(245), uint8(240), uint8(117), uint8(120), uint8(58), uint8(184), uint8(128), uint8(37), uint8(66), uint8(0), uint8(9), uint8(208), uint8(113), uint8(12), uint8(91), uint8(129), uint8(200), uint8(102), uint8(185), uint8(228), uint8(2), uint8(43), uint8(238), uint8(7), uint8(8), uint8(174), uint8(185), uint8(252), uint8(225), uint8(20), uint8(72), uint8(181), uint8(199), uint8(236), uint8(184), uint8(17), uint8(174), uint8(35), uint8(190), uint8(31), uint8(242), uint8(250), uint8(138), uint8(8), uint8(98), uint8(170), uint8(34), uint8(179), uint8(202), uint8(16), uint8(12), uint8(19), uint8(129), uint8(224), uint8(99), uint8(50), uint8(194), uint8(0), uint8(44), uint8(239), uint8(43), uint8(119), uint8(224), uint8(49), uint8(8), uint8(144), uint8(215), uint8(80), uint8(35), uint8(55), uint8(207), uint8(41), uint8(233), uint8(250), uint8(192), uint8(7), uint8(52), uint8(54), uint8(55), uint8(21), uint8(108), uint8(86), uint8(237), uint8(3), uint8(228), uint8(204), uint8(72), uint8(241), uint8(99), uint8(247), uint8(231), uint8(128), uint8(0), uint8(0), uint8(3), uint8(83), uint8(109), uint8(111), uint8(111), uint8(118), uint8(0), uint8(0), uint8(0), uint8(108), uint8(109), uint8(118), uint8(104), uint8(100), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(3), uint8(232), uint8(0), uint8(0), uint8(3), uint8(232), uint8(0), uint8(1), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(64), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(2), uint8(0), uint8(0), uint8(2), uint8(126), uint8(116), uint8(114), uint8(97), uint8(107), uint8(0), uint8(0), uint8(0), uint8(92), uint8(116), uint8(107), uint8(104), uint8(100), uint8(0), uint8(0), uint8(0), uint8(3), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(3), uint8(232), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(64), uint8(0), uint8(0), uint8(0), uint8(0), uint8(96), uint8(0), uint8(0), uint8(0), uint8(64), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(36), uint8(101), uint8(100), uint8(116), uint8(115), uint8(0), uint8(0), uint8(0), uint8(28), uint8(101), uint8(108), uint8(115), uint8(116), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(3), uint8(232), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(0), uint8(1), uint8(246), uint8(109), uint8(100), uint8(105), uint8(97), uint8(0), uint8(0), uint8(0), uint8(32), uint8(109), uint8(100), uint8(104), uint8(100), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(48), uint8(0), uint8(0), uint8(0), uint8(48), uint8(0), uint8(85), uint8(196), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(45), uint8(104), uint8(100), uint8(108), uint8(114), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(118), uint8(105), uint8(100), uint8(101), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(86), uint8(105), uint8(100), uint8(101), uint8(111), uint8(72), uint8(97), uint8(110), uint8(100), uint8(108), uint8(101), uint8(114), uint8(0), uint8(0), uint8(0), uint8(1), uint8(161), uint8(109), uint8(105), uint8(110), uint8(102), uint8(0), uint8(0), uint8(0), uint8(20), uint8(118), uint8(109), uint8(104), uint8(100), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(36), uint8(100), uint8(105), uint8(110), uint8(102), uint8(0), uint8(0), uint8(0), uint8(28), uint8(100), uint8(114), uint8(101), uint8(102), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(12), uint8(117), uint8(114), uint8(108), uint8(32), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(1), uint8(97), uint8(115), uint8(116), uint8(98), uint8(108), uint8(0), uint8(0), uint8(0), uint8(185), uint8(115), uint8(116), uint8(115), uint8(100), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(169), uint8(97), uint8(118), uint8(99), uint8(49), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(96), uint8(0), uint8(64), uint8(0), uint8(72), uint8(0), uint8(0), uint8(0), uint8(72), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(1), uint8(21), uint8(76), uint8(97), uint8(118), uint8(99), uint8(54), uint8(50), uint8(46), uint8(49), uint8(49), uint8(46), uint8(49), uint8(48), uint8(48), uint8(32), uint8(108), uint8(105), uint8(98), uint8(120), uint8(50), uint8(54), uint8(52), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(24), uint8(255), uint8(255), uint8(0), uint8(0), uint8(0), uint8(47), uint8(97), uint8(118), uint8(99), uint8(67), uint8(1), uint8(66), uint8(192), uint8(10), uint8(255), uint8(225), uint8(0), uint8(23), uint8(103), uint8(66), uint8(192), uint8(10), uint8(217), uint8(6), uint8(38), uint8(192), uint8(68), uint8(0), uint8(0), uint8(3), uint8(0), uint8(4), uint8(0), uint8(0), uint8(3), uint8(0), uint8(96), uint8(60), uint8(72), uint8(153), uint8(32), uint8(1), uint8(0), uint8(5), uint8(104), uint8(203), uint8(131), uint8(203), uint8(32), uint8(0), uint8(0), uint8(0), uint8(16), uint8(112), uint8(97), uint8(115), uint8(112), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(20), uint8(98), uint8(116), uint8(114), uint8(116), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(223), uint8(72), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(24), uint8(115), uint8(116), uint8(116), uint8(115), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(12), uint8(0), uint8(0), uint8(4), uint8(0), uint8(0), uint8(0), uint8(0), uint8(20), uint8(115), uint8(116), uint8(115), uint8(115), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(28), uint8(115), uint8(116), uint8(115), uint8(99), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(12), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(68), uint8(115), uint8(116), uint8(115), uint8(122), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(12), uint8(0), uint8(0), uint8(9), uint8(70), uint8(0), uint8(0), uint8(1), uint8(206), uint8(0), uint8(0), uint8(1), uint8(224), uint8(0), uint8(0), uint8(1), uint8(163), uint8(0), uint8(0), uint8(1), uint8(139), uint8(0), uint8(0), uint8(1), uint8(172), uint8(0), uint8(0), uint8(1), uint8(183), uint8(0), uint8(0), uint8(1), uint8(34), uint8(0), uint8(0), uint8(1), uint8(200), uint8(0), uint8(0), uint8(1), uint8(182), uint8(0), uint8(0), uint8(1), uint8(255), uint8(0), uint8(0), uint8(1), uint8(197), uint8(0), uint8(0), uint8(0), uint8(20), uint8(115), uint8(116), uint8(99), uint8(111), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(48), uint8(0), uint8(0), uint8(0), uint8(97), uint8(117), uint8(100), uint8(116), uint8(97), uint8(0), uint8(0), uint8(0), uint8(89), uint8(109), uint8(101), uint8(116), uint8(97), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(33), uint8(104), uint8(100), uint8(108), uint8(114), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(109), uint8(100), uint8(105), uint8(114), uint8(97), uint8(112), uint8(112), uint8(108), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(0), uint8(44), uint8(105), uint8(108), uint8(115), uint8(116), uint8(0), uint8(0), uint8(0), uint8(36), uint8(169), uint8(116), uint8(111), uint8(111), uint8(0), uint8(0), uint8(0), uint8(28), uint8(100), uint8(97), uint8(116), uint8(97), uint8(0), uint8(0), uint8(0), uint8(1), uint8(0), uint8(0), uint8(0), uint8(0), uint8(76), uint8(97), uint8(118), uint8(102), uint8(54), uint8(50), uint8(46), uint8(51), uint8(46), uint8(49), uint8(48), uint8(48)]

var host_bytes : uint8? = null

var host_length : int = 0

var host_picture : uint8? = null

var host_width : int = 0

var host_height : int = 0

var host_y_size : int = 0

var host_u_size : int = 0

var host_v_size : int = 0

[export]
def rotl32(var value : uint; var shift : uint) : uint {
    return value << shift | value >> 0x20 - shift
}
[export]
def fold_bytes(var bytes : uint8 const?; var length : int) : uint {
    var hash : uint = 0x811c9dc5
    var index : int = 0
    index = 0
    index
    while (index < length) {
        hash = uint(hash ^ uint(unsafe(bytes[index])))
        hash
        hash = uint(hash * 0x1000193)
        hash
        hash = uint(rotl32(hash, 0x5))
        hash
        index = index + 1
    }
    return hash
}
[export]
def memory_read_callback(var offset : int64; var buffer : uint64; var size : size_t; var token : uint64) : int {
    var input : MemoryInput? = unsafe(reinterpret<MemoryInput?>(token))
    if (offset < int64(0)) {
        return 1
    }
    if (offset + int64(size) > int64(input.length)) {
        return 1
    }
    memcpy(buffer, unsafe(unsafe(reinterpret<uint64>(unsafe(input.bytes + cast<size_t>(offset))))), size)
    return 0
}
[export]
def find_avc_track(var mp4 : MP4D_demux_t const?) : int {
    var index_0 : uint = uint(0)
    index_0 = uint(uint(0))
    index_0
    while (index_0 < mp4.track_count) {
        var track : MP4D_track_t const? = unsafe(mp4.track + index_0)
        if (track.handler_type == uint(1986618469) && track.object_type_indication == uint(33)) {
            return int(index_0)
        }
        index_0 = index_0 + 1
    }
    return -1
}
[export]
def sample_annexb_size(var sample : uint8 const?; var sample_bytes : int; var length_size : int) : int {
    var offset_0 : int = 0
    var total : int = 0
    while (offset_0 < sample_bytes) {
        var nal_size : int = 0
        var length_index : int = 0
        if (sample_bytes - offset_0 < length_size) {
            return -1
        }
        length_index = 0
        length_index
        while (length_index < length_size) {
            nal_size = nal_size << 8 | int(unsafe(sample[offset_0 + length_index]))
            nal_size
            length_index = length_index + 1
        }
        offset_0 = offset_0 + length_size
        offset_0
        if (nal_size < 0 || sample_bytes - offset_0 < nal_size) {
            return -1
        }
        total = total + 4 + nal_size
        total
        offset_0 = offset_0 + nal_size
        offset_0
    }
    return total
}
[export]
def infer_length_size(var sample_0 : uint8 const?; var sample_bytes_0 : int) : int {
    var candidate : int = 0
    candidate = 4
    candidate
    while (candidate >= 1) {
        if (sample_annexb_size(sample_0, sample_bytes_0, candidate) >= 0) {
            return candidate
        }
        candidate = candidate - 1
    }
    return 0
}
[export]
def detect_track_length_size(var mp4_0 : MP4D_demux_t const?; var track_index : int; var bytes_0 : uint8 const?; var total_bytes : int) : int {
    var sample_index : uint = uint(0)
    sample_index = uint(uint(0))
    sample_index
    while (sample_index < unsafe(mp4_0.track[track_index]).sample_count) {
        var frame_bytes : uint = uint(0)
        var offset_1 : uint64 = MP4D_frame_offset(mp4_0, uint(track_index), sample_index, unsafe(addr(frame_bytes)), null, null)
        if (frame_bytes == uint(0)) {
            continue
        }
        if (offset_1 + uint64(frame_bytes) > uint64(uint(total_bytes))) {
            return 0
        }
        return infer_length_size(unsafe(bytes_0 + offset_1), int(frame_bytes))
        sample_index = sample_index + 1
    }
    return 0
}
[export]
def output_picture_width(var storage : storage_t?) : int {
    return int(h264bsdPicWidth(storage)) * 16
}
[export]
def output_picture_height(var storage_0 : storage_t?) : int {
    return int(h264bsdPicHeight(storage_0)) * 16
}
[export]
def decode_access_unit(var state : DecoderState?; var bytes_1 : uint8 const?; var length_0 : int; var picture_ready : int?) : int {
    var offset_2 : int = 0
    *picture_ready = 0
    *picture_ready
    while (offset_2 < length_0) {
        var read_bytes : uint = uint(0)
        var result_0 : uint = h264bsdDecode(state.storage, cast<uint8?>(unsafe(bytes_1 + offset_2)), uint(length_0 - offset_2), 0x0, unsafe(addr(read_bytes)))
        if (result_0 == uint(H264BSD_ERROR) || result_0 == uint(H264BSD_PARAM_SET_ERROR) || result_0 == uint(H264BSD_MEMALLOC_ERROR)) {
            return 0
        }
        if (read_bytes == 0x0 && result_0 != uint(H264BSD_HDRS_RDY)) {
            return 0
        }
        offset_2 = offset_2 + int(read_bytes)
        offset_2
        if (result_0 == uint(H264BSD_HDRS_RDY)) {
            state.width = output_picture_width(state.storage)
            state.width
            state.height = output_picture_height(state.storage)
            state.height
        }
        if (result_0 == uint(H264BSD_PIC_RDY)) {
            var pic_id : uint = uint(0)
            var is_idr_pic : uint = uint(0)
            var num_err_mbs : uint = uint(0)
            state.picture = h264bsdNextOutputPicture(state.storage, unsafe(addr(pic_id)), unsafe(addr(is_idr_pic)), unsafe(addr(num_err_mbs)))
            state.picture
            state.width = output_picture_width(state.storage)
            state.width
            state.height = output_picture_height(state.storage)
            state.height
            *picture_ready = 1
            *picture_ready
        }
    }
    return 1
}
[export]
def decode_summary(var bytes_2 : uint8 const?; var length_1 : int; var frame_limit : int; var summary : DecodeSummary?) : int {
    var input_0 : MemoryInput
    var mp4_1 : MP4D_demux_t
    var track_index_0 : int = -1
    var track_length_size : int = 0
    var prefix_bytes : int = 0
    var max_sample_bytes : int = 0
    var scratch : uint8? = null
    var state_0 : DecoderState
    var sample_index_0 : int = 0
    memset(unsafe(unsafe(reinterpret<uint64>(summary))), 0, 4)
    memset(unsafe(unsafe(reinterpret<uint64>(unsafe(addr(mp4_1))))), 0, 4)
    input_0.bytes = bytes_2
    input_0.bytes
    input_0.length = length_1
    input_0.length
    if (MP4D_open(unsafe(addr(mp4_1)), memory_read_callback, unsafe(unsafe(reinterpret<uint64>(unsafe(addr(input_0))))), int64(length_1)) == 0) {
        return 0
    }
    track_index_0 = find_avc_track(unsafe(addr(mp4_1)))
    track_index_0
    if (track_index_0 < 0) {
        MP4D_close(unsafe(addr(mp4_1)))
        return 0
    }
    track_length_size = detect_track_length_size(unsafe(addr(mp4_1)), track_index_0, bytes_2, length_1)
    track_length_size
    if (track_length_size <= 0) {
        MP4D_close(unsafe(addr(mp4_1)))
        return 0
    }
    prefix_bytes = header_annexb_size(unsafe(addr(mp4_1)), track_index_0)
    prefix_bytes
    sample_index_0 = 0
    sample_index_0
    while (sample_index_0 < int(unsafe(mp4_1.track[track_index_0]).sample_count)) {
        var frame_bytes_0 : uint = uint(0)
        var offset_3 : uint64 = MP4D_frame_offset(unsafe(addr(mp4_1)), uint(track_index_0), uint(sample_index_0), unsafe(addr(frame_bytes_0)), null, null)
        var annexb_bytes : int = 0
        if (offset_3 + uint64(frame_bytes_0) > uint64(uint(length_1))) {
            MP4D_close(unsafe(addr(mp4_1)))
            return 0
        }
        annexb_bytes = sample_annexb_size(unsafe(bytes_2 + offset_3), int(frame_bytes_0), track_length_size)
        annexb_bytes
        if (annexb_bytes < 0) {
            MP4D_close(unsafe(addr(mp4_1)))
            return 0
        }
        if (annexb_bytes + prefix_bytes > max_sample_bytes) {
            max_sample_bytes = annexb_bytes + prefix_bytes
            max_sample_bytes
        }
        sample_index_0 = sample_index_0 + 1
    }
    scratch = unsafe(reinterpret<uint8?>(malloc(cast<size_t>(max_sample_bytes))))
    scratch
    if (scratch == null) {
        MP4D_close(unsafe(addr(mp4_1)))
        return 0
    }
    memset(unsafe(unsafe(reinterpret<uint64>(unsafe(addr(state_0))))), 0, 4)
    state_0.storage = h264bsdAlloc()
    state_0.storage
    if (state_0.storage == null) {
        MP4D_close(unsafe(addr(mp4_1)))
        return 0
    }
    if (h264bsdInit(state_0.storage, 0x0) != uint(H264BSD_RDY)) {
        h264bsdFree(state_0.storage)
        MP4D_close(unsafe(addr(mp4_1)))
        return 0
    }
    summary.combined_hash = uint(0x811c9dc5)
    summary.combined_hash
    sample_index_0 = 0
    sample_index_0
    while (sample_index_0 < int(unsafe(mp4_1.track[track_index_0]).sample_count)) {
        var frame_bytes_1 : uint = uint(0)
        var offset_4 : uint64 = MP4D_frame_offset(unsafe(addr(mp4_1)), uint(track_index_0), uint(sample_index_0), unsafe(addr(frame_bytes_1)), null, null)
        var sample_length : int = build_annexb_sample(unsafe(addr(mp4_1)), track_index_0, unsafe(bytes_2 + offset_4), int(frame_bytes_1), sample_index_0 == 0, scratch, max_sample_bytes, track_length_size)
        var picture_ready_0 : int = 0
        if (sample_length < 0) {
            h264bsdShutdown(state_0.storage)
            h264bsdFree(state_0.storage)
            MP4D_close(unsafe(addr(mp4_1)))
            return 0
        }
        if (decode_access_unit(unsafe(addr(state_0)), scratch, sample_length, unsafe(addr(picture_ready_0))) == 0) {
            h264bsdShutdown(state_0.storage)
            h264bsdFree(state_0.storage)
            MP4D_close(unsafe(addr(mp4_1)))
            return 0
        }
        if (picture_ready_0 != 0) {
            var picture_bytes : int = state_0.width * state_0.height * 3 / 2
            var frame_hash : uint = fold_bytes(state_0.picture, picture_bytes)
            if (summary.frame_count == 0) {
                summary.first_hash = uint(frame_hash)
                summary.first_hash
                summary.width = state_0.width
                summary.width
                summary.height = state_0.height
                summary.height
            }
            summary.last_hash = uint(frame_hash)
            summary.last_hash
            summary.combined_hash = uint(summary.combined_hash ^ frame_hash + uint(uint(summary.frame_count) * 0x9e3779b9))
            summary.combined_hash
            summary.combined_hash = uint(rotl32(summary.combined_hash, 0x7))
            summary.combined_hash
            summary.combined_hash = uint(summary.combined_hash + 0x7f4a7c15)
            summary.combined_hash
            summary.frame_count = summary.frame_count + 1
            summary.frame_count
            if (frame_limit > 0 && summary.frame_count >= frame_limit) {
                break
            }
        }
        sample_index_0 = sample_index_0 + 1
    }
    summary.combined_hash = uint(summary.combined_hash ^ uint(summary.width))
    summary.combined_hash
    summary.combined_hash = uint(rotl32(summary.combined_hash, 0x3))
    summary.combined_hash
    summary.combined_hash = uint(summary.combined_hash ^ uint(summary.height))
    summary.combined_hash
    summary.combined_hash = uint(rotl32(summary.combined_hash, 0x3))
    summary.combined_hash
    summary.combined_hash = uint(summary.combined_hash ^ uint(summary.frame_count))
    summary.combined_hash
    h264bsdShutdown(state_0.storage)
    h264bsdFree(state_0.storage)
    MP4D_close(unsafe(addr(mp4_1)))
    return summary.frame_count > 0
}
[export]
def decode_frame_yuv(var bytes_3 : uint8 const?; var length_2 : int; var frame_index : int; var picture : uint8??; var width : int?; var height : int?) : int {
    var input_1 : MemoryInput
    var mp4_2 : MP4D_demux_t
    var track_index_1 : int = -1
    var track_length_size_0 : int = 0
    var prefix_bytes_0 : int = 0
    var max_sample_bytes_0 : int = 0
    var scratch_0 : uint8? = null
    var state_1 : DecoderState
    var sample_index_1 : int = 0
    var picture_index : int = 0
    memset(unsafe(unsafe(reinterpret<uint64>(unsafe(addr(mp4_2))))), 0, 4)
    input_1.bytes = bytes_3
    input_1.bytes
    input_1.length = length_2
    input_1.length
    if (MP4D_open(unsafe(addr(mp4_2)), memory_read_callback, unsafe(unsafe(reinterpret<uint64>(unsafe(addr(input_1))))), int64(length_2)) == 0) {
        return 0
    }
    track_index_1 = find_avc_track(unsafe(addr(mp4_2)))
    track_index_1
    if (track_index_1 < 0) {
        MP4D_close(unsafe(addr(mp4_2)))
        return 0
    }
    track_length_size_0 = detect_track_length_size(unsafe(addr(mp4_2)), track_index_1, bytes_3, length_2)
    track_length_size_0
    if (track_length_size_0 <= 0) {
        MP4D_close(unsafe(addr(mp4_2)))
        return 0
    }
    prefix_bytes_0 = header_annexb_size(unsafe(addr(mp4_2)), track_index_1)
    prefix_bytes_0
    sample_index_1 = 0
    sample_index_1
    while (sample_index_1 < int(unsafe(mp4_2.track[track_index_1]).sample_count)) {
        var frame_bytes_2 : uint = uint(0)
        var offset_5 : uint64 = MP4D_frame_offset(unsafe(addr(mp4_2)), uint(track_index_1), uint(sample_index_1), unsafe(addr(frame_bytes_2)), null, null)
        var annexb_bytes_0 : int = sample_annexb_size(unsafe(bytes_3 + offset_5), int(frame_bytes_2), track_length_size_0)
        if (annexb_bytes_0 < 0) {
            MP4D_close(unsafe(addr(mp4_2)))
            return 0
        }
        if (annexb_bytes_0 + prefix_bytes_0 > max_sample_bytes_0) {
            max_sample_bytes_0 = annexb_bytes_0 + prefix_bytes_0
            max_sample_bytes_0
        }
        sample_index_1 = sample_index_1 + 1
    }
    scratch_0 = unsafe(reinterpret<uint8?>(malloc(cast<size_t>(max_sample_bytes_0))))
    scratch_0
    if (scratch_0 == null) {
        MP4D_close(unsafe(addr(mp4_2)))
        return 0
    }
    memset(unsafe(unsafe(reinterpret<uint64>(unsafe(addr(state_1))))), 0, 4)
    state_1.storage = h264bsdAlloc()
    state_1.storage
    if (state_1.storage == null) {
        MP4D_close(unsafe(addr(mp4_2)))
        return 0
    }
    if (h264bsdInit(state_1.storage, 0x0) != uint(H264BSD_RDY)) {
        h264bsdFree(state_1.storage)
        MP4D_close(unsafe(addr(mp4_2)))
        return 0
    }
    sample_index_1 = 0
    sample_index_1
    while (sample_index_1 < int(unsafe(mp4_2.track[track_index_1]).sample_count)) {
        var frame_bytes_3 : uint = uint(0)
        var offset_6 : uint64 = MP4D_frame_offset(unsafe(addr(mp4_2)), uint(track_index_1), uint(sample_index_1), unsafe(addr(frame_bytes_3)), null, null)
        var sample_length_0 : int = build_annexb_sample(unsafe(addr(mp4_2)), track_index_1, unsafe(bytes_3 + offset_6), int(frame_bytes_3), sample_index_1 == 0, scratch_0, max_sample_bytes_0, track_length_size_0)
        var picture_ready_1 : int = 0
        if (sample_length_0 < 0) {
            h264bsdShutdown(state_1.storage)
            h264bsdFree(state_1.storage)
            MP4D_close(unsafe(addr(mp4_2)))
            return 0
        }
        if (decode_access_unit(unsafe(addr(state_1)), scratch_0, sample_length_0, unsafe(addr(picture_ready_1))) == 0) {
            h264bsdShutdown(state_1.storage)
            h264bsdFree(state_1.storage)
            MP4D_close(unsafe(addr(mp4_2)))
            return 0
        }
        if (picture_ready_1 != 0) {
            if (picture_index == frame_index) {
                *picture = state_1.picture
                *picture
                *width = state_1.width
                *width
                *height = state_1.height
                *height
                h264bsdShutdown(state_1.storage)
                h264bsdFree(state_1.storage)
                MP4D_close(unsafe(addr(mp4_2)))
                return 1
            }
            picture_index = picture_index + 1
            picture_index
        }
        sample_index_1 = sample_index_1 + 1
    }
    h264bsdShutdown(state_1.storage)
    h264bsdFree(state_1.storage)
    MP4D_close(unsafe(addr(mp4_2)))
    return 0
}
[export]
def h264mp4_decode_hash(var frame_limit_0 : int) : int {
    var summary_0 : DecodeSummary
    shim_reset_heap()
    if (decode_summary(cast<uint8 const?>(unsafe(addr(sample_mp4_bytes[0]))), int(sample_mp4_len), frame_limit_0, unsafe(addr(summary_0))) == 0) {
        return -1
    }
    return int(summary_0.combined_hash)
}
[export]
def h264mp4_probe_width() : int {
    var summary_1 : DecodeSummary
    shim_reset_heap()
    if (decode_summary(cast<uint8 const?>(unsafe(addr(sample_mp4_bytes[0]))), int(sample_mp4_len), 1, unsafe(addr(summary_1))) == 0) {
        return -1
    }
    return summary_1.width
}
[export]
def h264mp4_probe_height() : int {
    var summary_2 : DecodeSummary
    shim_reset_heap()
    if (decode_summary(cast<uint8 const?>(unsafe(addr(sample_mp4_bytes[0]))), int(sample_mp4_len), 1, unsafe(addr(summary_2))) == 0) {
        return -1
    }
    return summary_2.height
}
[export]
def h264mp4_probe_frame_count(var frame_limit_1 : int) : int {
    var summary_3 : DecodeSummary
    shim_reset_heap()
    if (decode_summary(cast<uint8 const?>(unsafe(addr(sample_mp4_bytes[0]))), int(sample_mp4_len), frame_limit_1, unsafe(addr(summary_3))) == 0) {
        return -1
    }
    return summary_3.frame_count
}
[export]
def h264mp4_probe_first_frame_hash() : int {
    var summary_4 : DecodeSummary
    shim_reset_heap()
    if (decode_summary(cast<uint8 const?>(unsafe(addr(sample_mp4_bytes[0]))), int(sample_mp4_len), 1, unsafe(addr(summary_4))) == 0) {
        return -1
    }
    return int(summary_4.first_hash)
}
[export]
def h264mp4_probe_last_frame_hash(var frame_limit_2 : int) : int {
    var summary_5 : DecodeSummary
    shim_reset_heap()
    if (decode_summary(cast<uint8 const?>(unsafe(addr(sample_mp4_bytes[0]))), int(sample_mp4_len), frame_limit_2, unsafe(addr(summary_5))) == 0) {
        return -1
    }
    return int(summary_5.last_hash)
}
[export]
def h264mp4_probe_track_index() : int {
    var input_2 : MemoryInput
    var mp4_3 : MP4D_demux_t
    var track_index_2 : int = -1
    shim_reset_heap()
    memset(unsafe(unsafe(reinterpret<uint64>(unsafe(addr(mp4_3))))), 0, 4)
    input_2.bytes = cast<uint8 const?>(unsafe(addr(sample_mp4_bytes[0])))
    input_2.bytes
    input_2.length = int(sample_mp4_len)
    input_2.length
    if (MP4D_open(unsafe(addr(mp4_3)), memory_read_callback, unsafe(unsafe(reinterpret<uint64>(unsafe(addr(input_2))))), int64(sample_mp4_len)) == 0) {
        return -2
    }
    track_index_2 = find_avc_track(unsafe(addr(mp4_3)))
    track_index_2
    MP4D_close(unsafe(addr(mp4_3)))
    return track_index_2
}
[export]
def h264mp4_probe_sample0_size() : int {
    var input_3 : MemoryInput
    var mp4_4 : MP4D_demux_t
    var track_index_3 : int = -1
    var frame_bytes_4 : uint = uint(0)
    var offset_7 : uint64 = uint64(0)
    shim_reset_heap()
    memset(unsafe(unsafe(reinterpret<uint64>(unsafe(addr(mp4_4))))), 0, 4)
    input_3.bytes = cast<uint8 const?>(unsafe(addr(sample_mp4_bytes[0])))
    input_3.bytes
    input_3.length = int(sample_mp4_len)
    input_3.length
    if (MP4D_open(unsafe(addr(mp4_4)), memory_read_callback, unsafe(unsafe(reinterpret<uint64>(unsafe(addr(input_3))))), int64(sample_mp4_len)) == 0) {
        return -2
    }
    track_index_3 = find_avc_track(unsafe(addr(mp4_4)))
    track_index_3
    if (track_index_3 < 0) {
        MP4D_close(unsafe(addr(mp4_4)))
        return -1
    }
    offset_7 = uint64(MP4D_frame_offset(unsafe(addr(mp4_4)), uint(track_index_3), 0x0, unsafe(addr(frame_bytes_4)), null, null))
    offset_7
    MP4D_close(unsafe(addr(mp4_4)))
    if (offset_7 + uint64(frame_bytes_4) > uint64(sample_mp4_len)) {
        return -3
    }
    return int(frame_bytes_4)
}
[export]
def h264mp4_probe_sample_count() : int {
    var input_4 : MemoryInput
    var mp4_5 : MP4D_demux_t
    var track_index_4 : int = -1
    shim_reset_heap()
    memset(unsafe(unsafe(reinterpret<uint64>(unsafe(addr(mp4_5))))), 0, 4)
    input_4.bytes = cast<uint8 const?>(unsafe(addr(sample_mp4_bytes[0])))
    input_4.bytes
    input_4.length = int(sample_mp4_len)
    input_4.length
    if (MP4D_open(unsafe(addr(mp4_5)), memory_read_callback, unsafe(unsafe(reinterpret<uint64>(unsafe(addr(input_4))))), int64(sample_mp4_len)) == 0) {
        return -2
    }
    track_index_4 = find_avc_track(unsafe(addr(mp4_5)))
    track_index_4
    if (track_index_4 < 0) {
        MP4D_close(unsafe(addr(mp4_5)))
        return -1
    }
    return int(unsafe(mp4_5.track[track_index_4]).sample_count)
}
[export]
def h264mp4_probe_sample0_offset() : int {
    var input_5 : MemoryInput
    var mp4_6 : MP4D_demux_t
    var track_index_5 : int = -1
    var frame_bytes_5 : uint = uint(0)
    var offset_8 : uint64 = uint64(0)
    shim_reset_heap()
    memset(unsafe(unsafe(reinterpret<uint64>(unsafe(addr(mp4_6))))), 0, 4)
    input_5.bytes = cast<uint8 const?>(unsafe(addr(sample_mp4_bytes[0])))
    input_5.bytes
    input_5.length = int(sample_mp4_len)
    input_5.length
    if (MP4D_open(unsafe(addr(mp4_6)), memory_read_callback, unsafe(unsafe(reinterpret<uint64>(unsafe(addr(input_5))))), int64(sample_mp4_len)) == 0) {
        return -2
    }
    track_index_5 = find_avc_track(unsafe(addr(mp4_6)))
    track_index_5
    if (track_index_5 < 0) {
        MP4D_close(unsafe(addr(mp4_6)))
        return -1
    }
    offset_8 = uint64(MP4D_frame_offset(unsafe(addr(mp4_6)), uint(track_index_5), 0x0, unsafe(addr(frame_bytes_5)), null, null))
    offset_8
    MP4D_close(unsafe(addr(mp4_6)))
    return int(offset_8)
}
[export]
def h264mp4_probe_length_size() : int {
    var input_6 : MemoryInput
    var mp4_7 : MP4D_demux_t
    var track_index_6 : int = -1
    shim_reset_heap()
    memset(unsafe(unsafe(reinterpret<uint64>(unsafe(addr(mp4_7))))), 0, 4)
    input_6.bytes = cast<uint8 const?>(unsafe(addr(sample_mp4_bytes[0])))
    input_6.bytes
    input_6.length = int(sample_mp4_len)
    input_6.length
    if (MP4D_open(unsafe(addr(mp4_7)), memory_read_callback, unsafe(unsafe(reinterpret<uint64>(unsafe(addr(input_6))))), int64(sample_mp4_len)) == 0) {
        return -2
    }
    track_index_6 = find_avc_track(unsafe(addr(mp4_7)))
    track_index_6
    if (track_index_6 < 0) {
        MP4D_close(unsafe(addr(mp4_7)))
        return -1
    }
    return detect_track_length_size(unsafe(addr(mp4_7)), track_index_6, unsafe(addr(sample_mp4_bytes[0])), int(sample_mp4_len))
}
[export]
def h264mp4_probe_header_size() : int {
    var input_7 : MemoryInput
    var mp4_8 : MP4D_demux_t
    var track_index_7 : int = -1
    shim_reset_heap()
    memset(unsafe(unsafe(reinterpret<uint64>(unsafe(addr(mp4_8))))), 0, 4)
    input_7.bytes = cast<uint8 const?>(unsafe(addr(sample_mp4_bytes[0])))
    input_7.bytes
    input_7.length = int(sample_mp4_len)
    input_7.length
    if (MP4D_open(unsafe(addr(mp4_8)), memory_read_callback, unsafe(unsafe(reinterpret<uint64>(unsafe(addr(input_7))))), int64(sample_mp4_len)) == 0) {
        return -2
    }
    track_index_7 = find_avc_track(unsafe(addr(mp4_8)))
    track_index_7
    if (track_index_7 < 0) {
        MP4D_close(unsafe(addr(mp4_8)))
        return -1
    }
    return header_annexb_size(unsafe(addr(mp4_8)), track_index_7)
}
[export]
def h264mp4_probe_sample0_prefix() : int {
    var input_8 : MemoryInput
    var mp4_9 : MP4D_demux_t
    var track_index_8 : int = -1
    var length_size_0 : int = 0
    var frame_bytes_6 : uint = uint(0)
    var offset_9 : uint64 = uint64(0)
    var index_1 : int = 0
    var prefix : int = 0
    shim_reset_heap()
    memset(unsafe(unsafe(reinterpret<uint64>(unsafe(addr(mp4_9))))), 0, 4)
    input_8.bytes = cast<uint8 const?>(unsafe(addr(sample_mp4_bytes[0])))
    input_8.bytes
    input_8.length = int(sample_mp4_len)
    input_8.length
    if (MP4D_open(unsafe(addr(mp4_9)), memory_read_callback, unsafe(unsafe(reinterpret<uint64>(unsafe(addr(input_8))))), int64(sample_mp4_len)) == 0) {
        return -2
    }
    track_index_8 = find_avc_track(unsafe(addr(mp4_9)))
    track_index_8
    if (track_index_8 < 0) {
        MP4D_close(unsafe(addr(mp4_9)))
        return -1
    }
    length_size_0 = detect_track_length_size(unsafe(addr(mp4_9)), track_index_8, unsafe(addr(sample_mp4_bytes[0])), int(sample_mp4_len))
    length_size_0
    offset_9 = uint64(MP4D_frame_offset(unsafe(addr(mp4_9)), uint(track_index_8), 0x0, unsafe(addr(frame_bytes_6)), null, null))
    offset_9
    if (length_size_0 <= 0 || frame_bytes_6 < uint(length_size_0)) {
        MP4D_close(unsafe(addr(mp4_9)))
        return -3
    }
    index_1 = 0
    index_1
    while (index_1 < length_size_0) {
        prefix = prefix << 8 | int(unsafe(unsafe(addr(sample_mp4_bytes[0]))[offset_9 + uint64(index_1)]))
        prefix
        index_1 = index_1 + 1
    }
    MP4D_close(unsafe(addr(mp4_9)))
    return prefix
}
[export]
def h264mp4_probe_dsi_bytes() : int {
    var input_9 : MemoryInput
    var mp4_10 : MP4D_demux_t
    var track_index_9 : int = -1
    shim_reset_heap()
    memset(unsafe(unsafe(reinterpret<uint64>(unsafe(addr(mp4_10))))), 0, 4)
    input_9.bytes = cast<uint8 const?>(unsafe(addr(sample_mp4_bytes[0])))
    input_9.bytes
    input_9.length = int(sample_mp4_len)
    input_9.length
    if (MP4D_open(unsafe(addr(mp4_10)), memory_read_callback, unsafe(unsafe(reinterpret<uint64>(unsafe(addr(input_9))))), int64(sample_mp4_len)) == 0) {
        return -2
    }
    track_index_9 = find_avc_track(unsafe(addr(mp4_10)))
    track_index_9
    if (track_index_9 < 0) {
        MP4D_close(unsafe(addr(mp4_10)))
        return -1
    }
    return int(unsafe(mp4_10.track[track_index_9]).dsi_bytes)
}
[export]
def h264mp4_probe_dsi_word0() : int {
    var input_10 : MemoryInput
    var mp4_11 : MP4D_demux_t
    var track_index_10 : int = -1
    var index_2 : int = 0
    var value_0 : int = 0
    shim_reset_heap()
    memset(unsafe(unsafe(reinterpret<uint64>(unsafe(addr(mp4_11))))), 0, 4)
    input_10.bytes = cast<uint8 const?>(unsafe(addr(sample_mp4_bytes[0])))
    input_10.bytes
    input_10.length = int(sample_mp4_len)
    input_10.length
    if (MP4D_open(unsafe(addr(mp4_11)), memory_read_callback, unsafe(unsafe(reinterpret<uint64>(unsafe(addr(input_10))))), int64(sample_mp4_len)) == 0) {
        return -2
    }
    track_index_10 = find_avc_track(unsafe(addr(mp4_11)))
    track_index_10
    if (track_index_10 < 0 || unsafe(mp4_11.track[track_index_10]).dsi == null || unsafe(mp4_11.track[track_index_10]).dsi_bytes < uint(4)) {
        MP4D_close(unsafe(addr(mp4_11)))
        return -1
    }
    index_2 = 0
    index_2
    while (index_2 < 4) {
        value_0 = value_0 << 8 | int(unsafe(unsafe(mp4_11.track[track_index_10]).dsi[index_2]))
        value_0
        index_2 = index_2 + 1
    }
    MP4D_close(unsafe(addr(mp4_11)))
    return value_0
}
[export]
def h264mp4_probe_dsi_word1() : int {
    var input_11 : MemoryInput
    var mp4_12 : MP4D_demux_t
    var track_index_11 : int = -1
    var index_3 : int = 0
    var value_1 : int = 0
    shim_reset_heap()
    memset(unsafe(unsafe(reinterpret<uint64>(unsafe(addr(mp4_12))))), 0, 4)
    input_11.bytes = cast<uint8 const?>(unsafe(addr(sample_mp4_bytes[0])))
    input_11.bytes
    input_11.length = int(sample_mp4_len)
    input_11.length
    if (MP4D_open(unsafe(addr(mp4_12)), memory_read_callback, unsafe(unsafe(reinterpret<uint64>(unsafe(addr(input_11))))), int64(sample_mp4_len)) == 0) {
        return -2
    }
    track_index_11 = find_avc_track(unsafe(addr(mp4_12)))
    track_index_11
    if (track_index_11 < 0 || unsafe(mp4_12.track[track_index_11]).dsi == null || unsafe(mp4_12.track[track_index_11]).dsi_bytes < uint(8)) {
        MP4D_close(unsafe(addr(mp4_12)))
        return -1
    }
    index_3 = 4
    index_3
    while (index_3 < 8) {
        value_1 = value_1 << 8 | int(unsafe(unsafe(mp4_12.track[track_index_11]).dsi[index_3]))
        value_1
        index_3 = index_3 + 1
    }
    MP4D_close(unsafe(addr(mp4_12)))
    return value_1
}
[export]
def h264mp4_probe_first_decode_result() : int {
    var input_12 : MemoryInput
    var mp4_13 : MP4D_demux_t
    var track_index_12 : int = -1
    var track_length_size_1 : int = 0
    var prefix_bytes_1 : int = 0
    var frame_bytes_7 : uint = uint(0)
    var offset_10 : uint64 = uint64(0)
    var storage_1 : storage_t? = null
    var scratch_1 : uint8? = null
    var sample_length_1 : int = 0
    var read_bytes_0 : uint = uint(0)
    var result_1 : uint = uint(0)
    shim_reset_heap()
    input_12.bytes = unsafe(addr(sample_mp4_bytes[0]))
    input_12.bytes
    input_12.length = int(sample_mp4_len)
    input_12.length
    if (MP4D_open(unsafe(addr(mp4_13)), memory_read_callback, unsafe(unsafe(reinterpret<uint64>(unsafe(addr(input_12))))), int64(sample_mp4_len)) == 0) {
        return -2
    }
    track_index_12 = find_avc_track(unsafe(addr(mp4_13)))
    track_index_12
    if (track_index_12 < 0) {
        MP4D_close(unsafe(addr(mp4_13)))
        return -3
    }
    track_length_size_1 = detect_track_length_size(unsafe(addr(mp4_13)), track_index_12, unsafe(addr(sample_mp4_bytes[0])), int(sample_mp4_len))
    track_length_size_1
    prefix_bytes_1 = header_annexb_size(unsafe(addr(mp4_13)), track_index_12)
    prefix_bytes_1
    offset_10 = uint64(MP4D_frame_offset(unsafe(addr(mp4_13)), uint(track_index_12), 0x0, unsafe(addr(frame_bytes_7)), null, null))
    offset_10
    scratch_1 = unsafe(reinterpret<uint8?>(malloc(cast<size_t>(frame_bytes_7) + cast<size_t>(prefix_bytes_1) + cast<size_t>(0x40))))
    scratch_1
    storage_1 = h264bsdAlloc()
    storage_1
    if (scratch_1 == null || storage_1 == null) {
        MP4D_close(unsafe(addr(mp4_13)))
        return -4
    }
    if (h264bsdInit(storage_1, 0x0) != uint(H264BSD_RDY)) {
        h264bsdFree(storage_1)
        MP4D_close(unsafe(addr(mp4_13)))
        return -5
    }
    sample_length_1 = build_annexb_sample(unsafe(addr(mp4_13)), track_index_12, unsafe(unsafe(addr(sample_mp4_bytes[0])) + offset_10), int(frame_bytes_7), 1, scratch_1, int(frame_bytes_7) + prefix_bytes_1 + 64, track_length_size_1)
    sample_length_1
    if (sample_length_1 <= 0) {
        h264bsdShutdown(storage_1)
        h264bsdFree(storage_1)
        MP4D_close(unsafe(addr(mp4_13)))
        return -6
    }
    result_1 = uint(h264bsdDecode(storage_1, scratch_1, uint(sample_length_1), 0x0, unsafe(addr(read_bytes_0))))
    result_1
    h264bsdShutdown(storage_1)
    h264bsdFree(storage_1)
    MP4D_close(unsafe(addr(mp4_13)))
    return int(result_1)
}
[export]
def h264mp4_probe_first_decode_bytes() : int {
    var input_13 : MemoryInput
    var mp4_14 : MP4D_demux_t
    var track_index_13 : int = -1
    var track_length_size_2 : int = 0
    var prefix_bytes_2 : int = 0
    var frame_bytes_8 : uint = uint(0)
    var offset_11 : uint64 = uint64(0)
    var storage_2 : storage_t? = null
    var scratch_2 : uint8? = null
    var sample_length_2 : int = 0
    var read_bytes_1 : uint = uint(0)
    shim_reset_heap()
    input_13.bytes = unsafe(addr(sample_mp4_bytes[0]))
    input_13.bytes
    input_13.length = int(sample_mp4_len)
    input_13.length
    if (MP4D_open(unsafe(addr(mp4_14)), memory_read_callback, unsafe(unsafe(reinterpret<uint64>(unsafe(addr(input_13))))), int64(sample_mp4_len)) == 0) {
        return -2
    }
    track_index_13 = find_avc_track(unsafe(addr(mp4_14)))
    track_index_13
    if (track_index_13 < 0) {
        MP4D_close(unsafe(addr(mp4_14)))
        return -3
    }
    track_length_size_2 = detect_track_length_size(unsafe(addr(mp4_14)), track_index_13, unsafe(addr(sample_mp4_bytes[0])), int(sample_mp4_len))
    track_length_size_2
    prefix_bytes_2 = header_annexb_size(unsafe(addr(mp4_14)), track_index_13)
    prefix_bytes_2
    offset_11 = uint64(MP4D_frame_offset(unsafe(addr(mp4_14)), uint(track_index_13), 0x0, unsafe(addr(frame_bytes_8)), null, null))
    offset_11
    scratch_2 = unsafe(reinterpret<uint8?>(malloc(cast<size_t>(frame_bytes_8) + cast<size_t>(prefix_bytes_2) + cast<size_t>(0x40))))
    scratch_2
    storage_2 = h264bsdAlloc()
    storage_2
    if (scratch_2 == null || storage_2 == null) {
        MP4D_close(unsafe(addr(mp4_14)))
        return -4
    }
    if (h264bsdInit(storage_2, 0x0) != uint(H264BSD_RDY)) {
        h264bsdFree(storage_2)
        MP4D_close(unsafe(addr(mp4_14)))
        return -5
    }
    sample_length_2 = build_annexb_sample(unsafe(addr(mp4_14)), track_index_13, unsafe(unsafe(addr(sample_mp4_bytes[0])) + offset_11), int(frame_bytes_8), 1, scratch_2, int(frame_bytes_8) + prefix_bytes_2 + 64, track_length_size_2)
    sample_length_2
    if (sample_length_2 <= 0) {
        h264bsdShutdown(storage_2)
        h264bsdFree(storage_2)
        MP4D_close(unsafe(addr(mp4_14)))
        return -6
    }
    h264bsdDecode(storage_2, scratch_2, uint(sample_length_2), 0x0, unsafe(addr(read_bytes_1)))
    h264bsdShutdown(storage_2)
    h264bsdFree(storage_2)
    MP4D_close(unsafe(addr(mp4_14)))
    return int(read_bytes_1)
}
[export]
def h264mp4_host_alloc(var size_0 : int) : int {
    var result_2 : uint64 = null
    if (size_0 <= 0) {
        return 0
    }
    result_2 = malloc(cast<size_t>(size_0))
    result_2
    return int(unsafe(reinterpret<intptr_t>(result_2)))
}
[export]
def h264mp4_host_reset() : int {
    shim_reset_heap()
    host_bytes = null
    host_bytes
    host_length = 0
    host_length
    host_picture = null
    host_picture
    host_width = 0
    host_width
    host_height = 0
    host_height
    host_y_size = 0
    host_y_size
    host_u_size = 0
    host_u_size
    host_v_size = 0
    host_v_size
    return 1
}
[export]
def h264mp4_host_load(var bytes_ptr : int; var bytes_len : int) : int {
    if (bytes_ptr == 0 || bytes_len <= 0) {
        return 0
    }
    host_bytes = unsafe(reinterpret<uint8?>(cast<intptr_t>(bytes_ptr)))
    host_bytes
    host_length = bytes_len
    host_length
    host_picture = null
    host_picture
    host_width = 0
    host_width
    host_height = 0
    host_height
    host_y_size = 0
    host_y_size
    host_u_size = 0
    host_u_size
    host_v_size = 0
    host_v_size
    return 1
}
[export]
def h264mp4_host_decode_frame(var frame_index_0 : int) : int {
    var picture_0 : uint8? = null
    var width_0 : int = 0
    var height_0 : int = 0
    if (host_bytes == null || host_length <= 0 || frame_index_0 < 0) {
        return 0
    }
    if (decode_frame_yuv(host_bytes, host_length, frame_index_0, unsafe(addr(picture_0)), unsafe(addr(width_0)), unsafe(addr(height_0))) == 0) {
        return 0
    }
    host_picture = picture_0
    host_picture
    host_width = width_0
    host_width
    host_height = height_0
    host_height
    host_y_size = width_0 * height_0
    host_y_size
    host_u_size = host_y_size / 4
    host_u_size
    host_v_size = host_y_size / 4
    host_v_size
    return 1
}
[export]
def h264mp4_host_get_y_ptr() : int {
    return int(unsafe(reinterpret<intptr_t>(host_picture)))
}
[export]
def h264mp4_host_get_u_ptr() : int {
    if (host_picture == null) {
        return 0
    }
    return int(unsafe(reinterpret<intptr_t>(unsafe(host_picture + host_y_size))))
}
[export]
def h264mp4_host_get_v_ptr() : int {
    if (host_picture == null) {
        return 0
    }
    return int(unsafe(reinterpret<intptr_t>(unsafe(unsafe(host_picture + host_y_size) + host_u_size))))
}
[export]
def h264mp4_host_get_y_size() : int {
    return host_y_size
}
[export]
def h264mp4_host_get_u_size() : int {
    return host_u_size
}
[export]
def h264mp4_host_get_v_size() : int {
    return host_v_size
}
[export]
def h264mp4_host_get_width() : int {
    return host_width
}
[export]
def h264mp4_host_get_height() : int {
    return host_height
}
var NAL_MAX_TYPE_VALUE : int = 31

var NAL_FILLER_DATA : int = 12

var NAL_END_OF_STREAM : int = 11

var NAL_END_OF_SEQUENCE : int = 10

var NAL_ACCESS_UNIT_DELIMITER : int = 9

var NAL_PIC_PARAM_SET : int = 8

var NAL_SEQ_PARAM_SET : int = 7

var NAL_SEI : int = 6

var NAL_CODED_SLICE_IDR : int = 5

var NAL_CODED_SLICE : int = 1

var LONG_TERM : int = 3

var SHORT_TERM : int = 2

var NON_EXISTING : int = 1

var UNUSED : int = 0

var I_PCM : int = 31

var I_16x16_3_2_1 : int = 30

var I_16x16_2_2_1 : int = 29

var I_16x16_1_2_1 : int = 28

var I_16x16_0_2_1 : int = 27

var I_16x16_3_1_1 : int = 26

var I_16x16_2_1_1 : int = 25

var I_16x16_1_1_1 : int = 24

var I_16x16_0_1_1 : int = 23

var I_16x16_3_0_1 : int = 22

var I_16x16_2_0_1 : int = 21

var I_16x16_1_0_1 : int = 20

var I_16x16_0_0_1 : int = 19

var I_16x16_3_2_0 : int = 18

var I_16x16_2_2_0 : int = 17

var I_16x16_1_2_0 : int = 16

var I_16x16_0_2_0 : int = 15

var I_16x16_3_1_0 : int = 14

var I_16x16_2_1_0 : int = 13

var I_16x16_1_1_0 : int = 12

var I_16x16_0_1_0 : int = 11

var I_16x16_3_0_0 : int = 10

var I_16x16_2_0_0 : int = 9

var I_16x16_1_0_0 : int = 8

var I_16x16_0_0_0 : int = 7

var I_4x4 : int = 6

var P_8x8ref0 : int = 5

var P_8x8 : int = 4

var P_L0_L0_8x16 : int = 3

var P_L0_L0_16x8 : int = 2

var P_L0_16x16 : int = 1

var P_Skip : int = 0

var P_L0_4x4 : int = 3

var P_L0_4x8 : int = 2

var P_L0_8x4 : int = 1

var P_L0_8x8 : int = 0

var H264BSD_MEMALLOC_ERROR : int = 5

var H264BSD_PARAM_SET_ERROR : int = 4

var H264BSD_ERROR : int = 3

var H264BSD_HDRS_RDY : int = 2

var H264BSD_PIC_RDY : int = 1

var H264BSD_RDY : int = 0

