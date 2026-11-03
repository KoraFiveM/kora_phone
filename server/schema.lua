local NULL = Kora.sql.NULL
local COLLATE = 'utf8mb4_unicode_ci'

local function idColumn() return { name = 'id', type = 'bigint', unsigned = true, auto_increment = true } end
local function idRef(name, nullable)
    if nullable then return { name = name, type = 'bigint', unsigned = true, null = true, default = NULL } end
    return { name = name, type = 'bigint', unsigned = true }
end
local function createdAt() return { name = 'created_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' } } end
local function updatedAt()
    return { name = 'updated_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' }, on_update = 'CURRENT_TIMESTAMP' }
end
local function nullable(name, type) return { name = name, type = type, null = true, default = NULL } end
local function flag(name, default) return { name = name, type = 'tinyint(1)', default = default } end

QBPhoneSchema = {
    {
        name = 'phone_devices', collate = COLLATE,
        columns = {
            idColumn(),
            { name = 'owner_citizenid', type = 'varchar(64)' },
            { name = 'phone_number', type = 'varchar(24)' },
            { name = 'label', type = 'varchar(64)', default = 'Personal' },
            { name = 'settings_json', type = 'json' },
            nullable('pin_hash', 'char(64)'),
            nullable('pin_salt', 'char(32)'),
            { name = 'pin_failed_attempts', type = 'tinyint', unsigned = true, default = 0 },
            { name = 'pin_locked_until', type = 'int', unsigned = true, null = true, default = NULL },
            flag('is_active', 1),
            createdAt(), updatedAt(),
        },
        primary = { 'id' },
        indexes = {
            { name = 'uq_phone_devices_number', columns = { 'phone_number' }, unique = true },
            { name = 'idx_phone_devices_owner_active', columns = { 'owner_citizenid', 'is_active' } },
        },
    },
    {
        name = 'phone_media', collate = COLLATE,
        columns = {
            idColumn(), idRef('owner_device_id'),
            { name = 'storage_provider', type = 'varchar(32)' },
            { name = 'storage_key', type = 'varchar(512)' },
            { name = 'public_url', type = 'varchar(2048)' },
            { name = 'mime_type', type = 'varchar(64)' },
            { name = 'byte_size', type = 'bigint', unsigned = true },
            { name = 'width', type = 'int', unsigned = true, null = true, default = NULL },
            { name = 'height', type = 'int', unsigned = true, null = true, default = NULL },
            nullable('checksum', 'varchar(128)'),
            createdAt(), nullable('deleted_at', 'timestamp'),
        },
        primary = { 'id' },
        indexes = {
            { name = 'uq_phone_media_provider_key', columns = { 'storage_provider', 'storage_key' }, unique = true },
            { name = 'idx_phone_media_owner_page', columns = { 'owner_device_id', 'deleted_at', 'id' } },
        },
        foreign = {
            { name = 'fk_phone_media_owner', columns = { 'owner_device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' }, on_delete = 'CASCADE' },
        },
    },
    {
        name = 'phone_contacts', collate = COLLATE,
        columns = {
            idColumn(), idRef('owner_device_id'),
            { name = 'display_name', type = 'varchar(64)' },
            { name = 'phone_number', type = 'varchar(24)' },
            idRef('avatar_media_id', true),
            flag('is_favorite', 0),
            createdAt(), updatedAt(),
        },
        primary = { 'id' },
        indexes = { { name = 'uq_phone_contacts_owner_number', columns = { 'owner_device_id', 'phone_number' }, unique = true } },
        foreign = {
            { name = 'fk_phone_contacts_owner', columns = { 'owner_device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' }, on_delete = 'CASCADE' },
            { name = 'fk_phone_contacts_avatar_media', columns = { 'avatar_media_id' }, ref_table = 'phone_media', ref_columns = { 'id' }, on_delete = 'SET NULL' },
        },
    },
    {
        name = 'phone_conversations', collate = COLLATE,
        columns = {
            idColumn(),
            { name = 'type', type = 'enum', values = { 'direct', 'group' } },
            nullable('title', 'varchar(80)'),
            { name = 'direct_key', type = 'varchar(64)', null = true, default = NULL, after = 'title' },
            idRef('created_by_device_id'),
            createdAt(), updatedAt(),
        },
        primary = { 'id' },
        indexes = {
            { name = 'idx_phone_conversations_updated', columns = { 'updated_at', 'id' } },
            { name = 'uq_phone_conversations_direct_key', columns = { 'direct_key' }, unique = true },
        },
        foreign = {
            { name = 'fk_phone_conversations_creator', columns = { 'created_by_device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' } },
        },
    },
    {
        name = 'phone_conversation_members', collate = COLLATE,
        columns = {
            idRef('conversation_id'), idRef('device_id'),
            { name = 'joined_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' } },
            nullable('left_at', 'timestamp'),
            idRef('last_read_message_id', true),
            flag('is_muted', 0),
        },
        primary = { 'conversation_id', 'device_id' },
        indexes = { { name = 'idx_phone_members_device', columns = { 'device_id', 'left_at' } } },
        foreign = {
            { name = 'fk_phone_members_conversation', columns = { 'conversation_id' }, ref_table = 'phone_conversations', ref_columns = { 'id' }, on_delete = 'CASCADE' },
            { name = 'fk_phone_members_device', columns = { 'device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' }, on_delete = 'CASCADE' },
        },
    },
    {
        name = 'phone_messages', collate = COLLATE,
        columns = {
            idColumn(), idRef('conversation_id'), idRef('sender_device_id'),
            { name = 'message_type', type = 'enum', values = { 'text', 'image', 'video', 'location', 'system' }, default = 'text', modify = true },
            nullable('body', 'text'),
            idRef('media_id', true), idRef('reply_to_id', true),
            nullable('client_request_id', 'varchar(64)'),
            createdAt(), nullable('edited_at', 'timestamp'), nullable('deleted_at', 'timestamp'),
        },
        primary = { 'id' },
        indexes = {
            { name = 'uq_phone_messages_idempotency', columns = { 'sender_device_id', 'client_request_id' }, unique = true },
            { name = 'idx_phone_messages_conversation_id', columns = { 'conversation_id', 'id' } },
        },
        foreign = {
            { name = 'fk_phone_messages_conversation', columns = { 'conversation_id' }, ref_table = 'phone_conversations', ref_columns = { 'id' }, on_delete = 'CASCADE' },
            { name = 'fk_phone_messages_sender', columns = { 'sender_device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' } },
            { name = 'fk_phone_messages_reply', columns = { 'reply_to_id' }, ref_table = 'phone_messages', ref_columns = { 'id' }, on_delete = 'SET NULL' },
            { name = 'fk_phone_messages_media', columns = { 'media_id' }, ref_table = 'phone_media', ref_columns = { 'id' }, on_delete = 'SET NULL' },
        },
    },
    {
        name = 'phone_message_deletions', collate = COLLATE,
        columns = {
            idRef('message_id'), idRef('device_id'),
            { name = 'deleted_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' } },
        },
        primary = { 'message_id', 'device_id' },
        indexes = { { name = 'idx_phone_message_deletions_device', columns = { 'device_id', 'message_id' } } },
        foreign = {
            { name = 'fk_phone_message_deletions_message', columns = { 'message_id' }, ref_table = 'phone_messages', ref_columns = { 'id' }, on_delete = 'CASCADE' },
            { name = 'fk_phone_message_deletions_device', columns = { 'device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' }, on_delete = 'CASCADE' },
        },
    },
    {
        name = 'phone_calls', collate = COLLATE,
        columns = {
            { name = 'id', type = 'char(36)' },
            idRef('caller_device_id'), idRef('callee_device_id'),
            { name = 'caller_number_snapshot', type = 'varchar(24)' },
            { name = 'callee_number_snapshot', type = 'varchar(24)' },
            { name = 'status', type = 'enum', values = { 'ringing', 'active', 'ended', 'rejected', 'missed', 'cancelled' } },
            { name = 'voice_channel', type = 'int', unsigned = true },
            { name = 'started_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' } },
            nullable('answered_at', 'timestamp'), nullable('ended_at', 'timestamp'), nullable('ended_reason', 'varchar(48)'),
        },
        primary = { 'id' },
        indexes = {
            { name = 'idx_phone_calls_caller_history', columns = { 'caller_device_id', 'started_at', 'id' } },
            { name = 'idx_phone_calls_callee_history', columns = { 'callee_device_id', 'started_at', 'id' } },
            { name = 'idx_phone_calls_unfinished', columns = { 'status', 'started_at' } },
        },
        foreign = {
            { name = 'fk_phone_calls_caller', columns = { 'caller_device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' } },
            { name = 'fk_phone_calls_callee', columns = { 'callee_device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' } },
        },
    },
    {
        name = 'phone_economy_audit', collate = COLLATE,
        columns = {
            idColumn(), idRef('sender_device_id'), idRef('recipient_device_id'),
            { name = 'sender_citizenid', type = 'varchar(64)' },
            { name = 'recipient_citizenid', type = 'varchar(64)' },
            { name = 'amount', type = 'bigint', unsigned = true },
            { name = 'status', type = 'enum', values = { 'pending', 'completed', 'rejected', 'rolled_back', 'manual_review' }, default = 'pending' },
            { name = 'client_request_id', type = 'varchar(64)' },
            nullable('failure_code', 'varchar(48)'),
            createdAt(), nullable('completed_at', 'timestamp'),
        },
        primary = { 'id' },
        indexes = {
            { name = 'uq_phone_economy_idempotency', columns = { 'sender_citizenid', 'client_request_id' }, unique = true },
            { name = 'idx_phone_economy_sender_device', columns = { 'sender_device_id', 'id' } },
            { name = 'idx_phone_economy_recipient_device', columns = { 'recipient_device_id', 'id' } },
            { name = 'idx_phone_economy_status', columns = { 'status', 'created_at' } },
        },
        foreign = {
            { name = 'fk_phone_economy_sender_device', columns = { 'sender_device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' } },
            { name = 'fk_phone_economy_recipient_device', columns = { 'recipient_device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' } },
        },
        checks = { { name = 'chk_phone_economy_positive_amount', expr = '`amount` > 0' } },
    },
    {
        name = 'phone_social_profiles', collate = COLLATE,
        columns = {
            idColumn(), idRef('device_id'),
            { name = 'handle', type = 'varchar(24)' },
            { name = 'display_name', type = 'varchar(64)' },
            { name = 'bio', type = 'varchar(280)', default = '' },
            idRef('avatar_media_id', true),
            flag('is_private', 0), flag('is_suspended', 0),
            createdAt(), updatedAt(),
        },
        primary = { 'id' },
        indexes = {
            { name = 'uq_phone_social_profile_device', columns = { 'device_id' }, unique = true },
            { name = 'uq_phone_social_profile_handle', columns = { 'handle' }, unique = true },
        },
        foreign = {
            { name = 'fk_phone_social_profile_device', columns = { 'device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' }, on_delete = 'CASCADE' },
        },
    },
    {
        name = 'phone_social_posts', collate = COLLATE,
        columns = {
            idColumn(), idRef('author_profile_id'),
            { name = 'body', type = 'varchar(5000)' },
            { name = 'media_id', type = 'bigint', unsigned = true, null = true, default = NULL, after = 'body' },
            { name = 'client_request_id', type = 'varchar(64)' },
            createdAt(), nullable('deleted_at', 'timestamp'),
        },
        primary = { 'id' },
        indexes = {
            { name = 'uq_phone_social_post_request', columns = { 'author_profile_id', 'client_request_id' }, unique = true },
            { name = 'idx_phone_social_posts_feed', columns = { 'deleted_at', 'id' } },
            { name = 'idx_phone_social_posts_media', columns = { 'media_id' } },
        },
        foreign = {
            { name = 'fk_phone_social_post_author', columns = { 'author_profile_id' }, ref_table = 'phone_social_profiles', ref_columns = { 'id' }, on_delete = 'CASCADE' },
            { name = 'fk_phone_social_posts_media', columns = { 'media_id' }, ref_table = 'phone_media', ref_columns = { 'id' }, on_delete = 'SET NULL' },
        },
    },
    {
        name = 'phone_social_comments', collate = COLLATE,
        columns = {
            idColumn(), idRef('post_id'), idRef('author_profile_id'),
            { name = 'body', type = 'varchar(1000)' },
            { name = 'client_request_id', type = 'varchar(64)' },
            createdAt(), nullable('deleted_at', 'timestamp'),
        },
        primary = { 'id' },
        indexes = {
            { name = 'uq_phone_social_comment_request', columns = { 'author_profile_id', 'client_request_id' }, unique = true },
            { name = 'idx_phone_social_comments_post', columns = { 'post_id', 'deleted_at', 'id' } },
        },
        foreign = {
            { name = 'fk_phone_social_comment_post', columns = { 'post_id' }, ref_table = 'phone_social_posts', ref_columns = { 'id' }, on_delete = 'CASCADE' },
            { name = 'fk_phone_social_comment_author', columns = { 'author_profile_id' }, ref_table = 'phone_social_profiles', ref_columns = { 'id' }, on_delete = 'CASCADE' },
        },
    },
    {
        name = 'phone_social_likes', collate = COLLATE,
        columns = { idRef('post_id'), idRef('profile_id'), createdAt() },
        primary = { 'post_id', 'profile_id' },
        foreign = {
            { name = 'fk_phone_social_like_post', columns = { 'post_id' }, ref_table = 'phone_social_posts', ref_columns = { 'id' }, on_delete = 'CASCADE' },
            { name = 'fk_phone_social_like_profile', columns = { 'profile_id' }, ref_table = 'phone_social_profiles', ref_columns = { 'id' }, on_delete = 'CASCADE' },
        },
    },
    {
        name = 'phone_social_follows', collate = COLLATE,
        columns = { idRef('follower_profile_id'), idRef('following_profile_id'), createdAt() },
        primary = { 'follower_profile_id', 'following_profile_id' },
        foreign = {
            { name = 'fk_phone_social_follow_follower', columns = { 'follower_profile_id' }, ref_table = 'phone_social_profiles', ref_columns = { 'id' }, on_delete = 'CASCADE' },
            { name = 'fk_phone_social_follow_following', columns = { 'following_profile_id' }, ref_table = 'phone_social_profiles', ref_columns = { 'id' }, on_delete = 'CASCADE' },
        },
    },
    {
        name = 'phone_blocks', collate = COLLATE,
        columns = { idRef('blocker_device_id'), idRef('blocked_device_id'), createdAt() },
        primary = { 'blocker_device_id', 'blocked_device_id' },
        foreign = {
            { name = 'fk_phone_block_blocker', columns = { 'blocker_device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' }, on_delete = 'CASCADE' },
            { name = 'fk_phone_block_blocked', columns = { 'blocked_device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' }, on_delete = 'CASCADE' },
        },
    },
    {
        name = 'phone_market_listings', collate = COLLATE,
        columns = {
            idColumn(), idRef('owner_device_id'),
            { name = 'title', type = 'varchar(80)' },
            { name = 'description', type = 'varchar(2000)', default = '' },
            { name = 'category', type = 'enum', values = { 'vehicle', 'property', 'electronics', 'services', 'other' }, default = 'other' },
            { name = 'price', type = 'bigint', unsigned = true },
            { name = 'client_request_id', type = 'varchar(64)' },
            { name = 'status', type = 'enum', values = { 'active', 'sold', 'removed' }, default = 'active' },
            createdAt(), updatedAt(),
        },
        primary = { 'id' },
        indexes = {
            { name = 'uq_phone_market_request', columns = { 'owner_device_id', 'client_request_id' }, unique = true },
            { name = 'idx_phone_market_feed', columns = { 'status', 'id' } },
        },
        foreign = {
            { name = 'fk_phone_market_owner', columns = { 'owner_device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' }, on_delete = 'CASCADE' },
        },
    },
    {
        name = 'phone_reports', collate = COLLATE,
        columns = {
            idColumn(), idRef('reporter_device_id'),
            { name = 'target_type', type = 'enum', values = { 'profile', 'post', 'comment', 'listing' } },
            idRef('target_id'),
            { name = 'reason', type = 'enum', values = { 'spam', 'harassment', 'scam', 'illegal', 'other' } },
            { name = 'details', type = 'varchar(1000)', default = '' },
            { name = 'snapshot_json', type = 'json' },
            { name = 'status', type = 'enum', values = { 'open', 'reviewing', 'resolved', 'dismissed' }, default = 'open' },
            nullable('assigned_citizenid', 'varchar(64)'), nullable('resolution_note', 'varchar(1000)'),
            createdAt(), updatedAt(),
        },
        primary = { 'id' },
        indexes = {
            { name = 'uq_phone_report_repeat', columns = { 'reporter_device_id', 'target_type', 'target_id' }, unique = true },
            { name = 'idx_phone_reports_queue', columns = { 'status', 'id' } },
        },
        foreign = {
            { name = 'fk_phone_report_reporter', columns = { 'reporter_device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' }, on_delete = 'CASCADE' },
        },
    },
    {
        name = 'phone_moderation_audit', collate = COLLATE,
        columns = {
            idColumn(),
            { name = 'actor_citizenid', type = 'varchar(64)' },
            { name = 'action', type = 'varchar(48)' },
            { name = 'target_type', type = 'varchar(24)' },
            idRef('target_id'),
            { name = 'reason', type = 'varchar(1000)' },
            { name = 'metadata_json', type = 'json' },
            createdAt(),
        },
        primary = { 'id' },
        indexes = { { name = 'idx_phone_moderation_audit_target', columns = { 'target_type', 'target_id', 'id' } } },
    },
    {
        name = 'phone_items', collate = COLLATE,
        columns = {
            idRef('device_id'),
            { name = 'kind', type = 'enum', values = { 'note', 'alarm', 'station' } },
            { name = 'item_key', type = 'varchar(64)' },
            { name = 'payload', type = 'text' },
            updatedAt(),
        },
        primary = { 'device_id', 'kind', 'item_key' },
        indexes = { { name = 'idx_phone_items_updated', columns = { 'device_id', 'kind', 'updated_at' } } },
        foreign = {
            { name = 'fk_phone_items_device', columns = { 'device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' }, on_delete = 'CASCADE' },
        },
    },
    {
        name = 'phone_mail', collate = COLLATE,
        columns = {
            idColumn(), idRef('sender_device_id'), idRef('recipient_device_id'),
            { name = 'subject', type = 'varchar(120)' },
            { name = 'body', type = 'text' },
            nullable('client_request_id', 'varchar(64)'),
            createdAt(), nullable('read_at', 'timestamp'),
            flag('sender_deleted', 0), flag('recipient_deleted', 0),
        },
        primary = { 'id' },
        indexes = {
            { name = 'uq_phone_mail_idempotency', columns = { 'sender_device_id', 'client_request_id' }, unique = true },
            { name = 'idx_phone_mail_inbox', columns = { 'recipient_device_id', 'recipient_deleted', 'id' } },
            { name = 'idx_phone_mail_sent', columns = { 'sender_device_id', 'sender_deleted', 'id' } },
        },
        foreign = {
            { name = 'fk_phone_mail_sender', columns = { 'sender_device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' }, on_delete = 'CASCADE' },
            { name = 'fk_phone_mail_recipient', columns = { 'recipient_device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' }, on_delete = 'CASCADE' },
        },
    },
    {
        name = 'phone_cloud_accounts', collate = COLLATE,
        columns = {
            { name = 'id', type = 'varchar(64)' },
            { name = 'owner_citizenid', type = 'varchar(64)' },
            { name = 'recovery_hash', type = 'char(64)' },
            nullable('snapshot_json', 'longtext'),
            { name = 'revision', type = 'int', default = 0 },
            createdAt(),
        },
        primary = { 'id' },
        indexes = { { name = 'cloud_owner', columns = { 'owner_citizenid' } } },
    },
    {
        name = 'phone_handsets', collate = COLLATE,
        columns = {
            { name = 'id', type = 'varchar(64)' },
            { name = 'model', type = 'varchar(12)' },
            idRef('device_id'),
            nullable('account_id', 'varchar(64)'), nullable('face_citizenid', 'varchar(64)'), nullable('pin_kdf', 'varchar(200)'),
            { name = 'is_reset', type = 'tinyint', default = 0 },
            { name = 'cloud_revision', type = 'int', default = 0 },
        },
        primary = { 'id' },
        indexes = {
            { name = 'device_id', columns = { 'device_id' }, unique = true },
            { name = 'account_id', columns = { 'account_id' } },
        },
        foreign = {
            { name = 'phone_handsets_ibfk_1', columns = { 'device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' } },
            { name = 'phone_handsets_ibfk_2', columns = { 'account_id' }, ref_table = 'phone_cloud_accounts', ref_columns = { 'id' } },
        },
    },
    {
        name = 'phone_sims', collate = COLLATE,
        columns = {
            { name = 'id', type = 'varchar(64)' },
            { name = 'phone_number', type = 'varchar(24)' },
            { name = 'owner_citizenid', type = 'varchar(64)' },
            { name = 'status', type = 'enum', values = { 'active', 'blocked', 'revoked' }, default = 'active' },
            { name = 'active_number', type = 'varchar(24)', generated = { expr = "CASE WHEN status='active' THEN phone_number ELSE NULL END" } },
            nullable('handset_id', 'varchar(64)'),
            createdAt(),
        },
        primary = { 'id' },
        indexes = {
            { name = 'active_number', columns = { 'active_number' }, unique = true },
            { name = 'handset_id', columns = { 'handset_id' }, unique = true },
            { name = 'sim_number', columns = { 'phone_number', 'status' } },
        },
        foreign = {
            { name = 'phone_sims_ibfk_1', columns = { 'handset_id' }, ref_table = 'phone_handsets', ref_columns = { 'id' } },
        },
    },
    {
        name = 'phone_legacy_claims', collate = COLLATE,
        columns = {
            idRef('device_id'),
            { name = 'citizenid', type = 'varchar(64)' },
            nullable('handset_id', 'varchar(64)'),
            { name = 'account_id', type = 'varchar(64)' },
            nullable('claimed_at', 'timestamp'),
        },
        primary = { 'device_id' },
        indexes = {
            { name = 'handset_id', columns = { 'handset_id' }, unique = true },
            { name = 'legacy_character', columns = { 'citizenid' } },
        },
    },
    {
        name = 'phone_mailboxes', collate = COLLATE,
        columns = {
            idColumn(), idRef('device_id'),
            { name = 'peer_number', type = 'varchar(24)' },
            { name = 'sender_number', type = 'varchar(24)' },
            { name = 'body', type = 'text' },
            idRef('media_id', true),
            { name = 'request_id', type = 'varchar(100)' },
            createdAt(),
            { name = 'is_read', type = 'tinyint', default = 0 },
            { name = 'is_outgoing', type = 'tinyint', default = 0 },
        },
        primary = { 'id' },
        indexes = {
            { name = 'delivery_once', columns = { 'device_id', 'request_id' }, unique = true },
            { name = 'mailbox_thread', columns = { 'device_id', 'peer_number', 'id' } },
        },
        foreign = {
            { name = 'phone_mailboxes_ibfk_1', columns = { 'device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' } },
        },
    },
    {
        name = 'phone_threads', collate = COLLATE,
        columns = { idColumn(), idRef('device_id'), { name = 'peer_number', type = 'varchar(24)' } },
        primary = { 'id' },
        indexes = { { name = 'own_thread', columns = { 'device_id', 'peer_number' }, unique = true } },
        foreign = {
            { name = 'phone_threads_ibfk_1', columns = { 'device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' } },
        },
    },
    {
        name = 'phone_migration_issues', collate = COLLATE,
        columns = {
            idColumn(), idRef('device_id', true),
            { name = 'issue_key', type = 'varchar(160)' },
            { name = 'detail', type = 'text' },
            createdAt(),
        },
        primary = { 'id' },
        indexes = { { name = 'issue_key', columns = { 'issue_key' }, unique = true } },
    },
    {
        name = 'phone_gallery_links', collate = COLLATE,
        columns = { idRef('device_id'), idRef('media_id') },
        primary = { 'device_id', 'media_id' },
        indexes = { { name = 'media_id', columns = { 'media_id' } } },
        foreign = {
            { name = 'phone_gallery_links_ibfk_1', columns = { 'device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' } },
            { name = 'phone_gallery_links_ibfk_2', columns = { 'media_id' }, ref_table = 'phone_media', ref_columns = { 'id' } },
        },
    },
    {
        name = 'phone_cloud_media', collate = COLLATE,
        columns = { { name = 'account_id', type = 'varchar(64)' }, idRef('media_id') },
        primary = { 'account_id', 'media_id' },
        indexes = { { name = 'media_id', columns = { 'media_id' } } },
        foreign = {
            { name = 'phone_cloud_media_ibfk_1', columns = { 'account_id' }, ref_table = 'phone_cloud_accounts', ref_columns = { 'id' } },
            { name = 'phone_cloud_media_ibfk_2', columns = { 'media_id' }, ref_table = 'phone_media', ref_columns = { 'id' } },
        },
    },
    {
        name = 'phone_upgrade_state', collate = COLLATE,
        columns = {
            { name = 'name', type = 'varchar(64)' },
            { name = 'completed_at', type = 'timestamp', default = { raw = 'CURRENT_TIMESTAMP' } },
        },
        primary = { 'name' },
    },
    {
        name = 'phone_call_hidden', collate = COLLATE,
        columns = { idRef('device_id'), { name = 'call_id', type = 'char(36)' } },
        primary = { 'device_id', 'call_id' },
        indexes = { { name = 'call_id', columns = { 'call_id' } } },
        foreign = {
            { name = 'phone_call_hidden_ibfk_1', columns = { 'device_id' }, ref_table = 'phone_devices', ref_columns = { 'id' } },
            { name = 'phone_call_hidden_ibfk_2', columns = { 'call_id' }, ref_table = 'phone_calls', ref_columns = { 'id' } },
        },
    },
    {
        name = 'phone_sim_replacements', collate = COLLATE,
        columns = {
            { name = 'id', type = 'varchar(64)' },
            { name = 'old_sim_id', type = 'varchar(64)' },
            { name = 'new_sim_id', type = 'varchar(64)' },
            { name = 'handset_id', type = 'varchar(64)' },
            { name = 'citizenid', type = 'varchar(64)' },
            { name = 'state', type = 'enum', values = { 'prepared', 'complete', 'cancelled' }, default = 'prepared' },
            createdAt(),
        },
        primary = { 'id' },
        indexes = { { name = 'new_sim_id', columns = { 'new_sim_id' }, unique = true } },
    },
    {
        name = 'phone_legacy_mail', collate = COLLATE,
        columns = {
            idColumn(), idRef('legacy_source_id', true),
            { name = 'citizenid', type = 'varchar(64)' },
            { name = 'sender', type = 'varchar(100)' },
            { name = 'subject', type = 'varchar(120)' },
            { name = 'body', type = 'text' },
            nullable('button_json', 'longtext'),
            nullable('read_at', 'timestamp'), nullable('deleted_at', 'timestamp'),
            createdAt(),
        },
        primary = { 'id' },
        indexes = {
            { name = 'legacy_source_id', columns = { 'legacy_source_id' }, unique = true },
            { name = 'legacy_mail_owner', columns = { 'citizenid', 'deleted_at', 'id' } },
        },
    },
    {
        name = 'phone_legacy_transactions', collate = COLLATE,
        columns = {
            idColumn(),
            { name = 'citizenid', type = 'varchar(64)' },
            { name = 'title', type = 'varchar(100)' },
            { name = 'message', type = 'varchar(1000)' },
            createdAt(),
        },
        primary = { 'id' },
        indexes = { { name = 'legacy_transactions_owner', columns = { 'citizenid', 'id' } } },
    },
}
