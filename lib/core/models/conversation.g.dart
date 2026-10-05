// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ConversationAdapter extends TypeAdapter<Conversation> {
  @override
  final int typeId = 1;

  @override
  Conversation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Conversation(
      id: fields[0] as String?,
      title: fields[1] as String,
      createdAt: fields[2] as DateTime?,
      updatedAt: fields[3] as DateTime?,
      messageIds: (fields[4] as List?)?.cast<String>(),
      isPinned: fields[5] as bool,
      mcpServerIds: (fields[6] as List?)?.cast<String>(),
      assistantId: fields[7] as String?,
      truncateIndex: fields[8] as int?,
      versionSelections: (fields[9] as Map?)?.cast<String, int>(),
      summary: fields[10] as String?,
      lastSummarizedMessageCount: fields[11] as int?,
      chatSuggestions: (fields[12] as List?)?.cast<String>(),
      hostedSynced: fields[13] == null ? false : fields[13] as bool,
      chatModelProvider: fields[14] as String?,
      chatModelId: fields[15] as String?,
      contextSummary: fields[16] as String?,
      contextSummaryThroughSeq: fields[17] as int?,
      contextSummaryVersion: fields[18] == null ? 0 : fields[18] as int,
      contextCompactionStatus: fields[19] == null
          ? 'idle'
          : fields[19] as String,
      contextCompactionMessageId: fields[20] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Conversation obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.updatedAt)
      ..writeByte(4)
      ..write(obj.messageIds)
      ..writeByte(5)
      ..write(obj.isPinned)
      ..writeByte(6)
      ..write(obj.mcpServerIds)
      ..writeByte(7)
      ..write(obj.assistantId)
      ..writeByte(8)
      ..write(obj.truncateIndex)
      ..writeByte(9)
      ..write(obj.versionSelections)
      ..writeByte(10)
      ..write(obj.summary)
      ..writeByte(11)
      ..write(obj.lastSummarizedMessageCount)
      ..writeByte(12)
      ..write(obj.chatSuggestions)
      ..writeByte(13)
      ..write(obj.hostedSynced)
      ..writeByte(14)
      ..write(obj.chatModelProvider)
      ..writeByte(15)
      ..write(obj.chatModelId)
      ..writeByte(16)
      ..write(obj.contextSummary)
      ..writeByte(17)
      ..write(obj.contextSummaryThroughSeq)
      ..writeByte(18)
      ..write(obj.contextSummaryVersion)
      ..writeByte(19)
      ..write(obj.contextCompactionStatus)
      ..writeByte(20)
      ..write(obj.contextCompactionMessageId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
