QBPhone.Repositories = QBPhone.Repositories or {}
local Social = {}
QBPhone.Repositories.Social = Social

function Social.profileByDevice(deviceId)
    return MySQL.single.await([[SELECT id, device_id AS deviceId, handle, display_name AS displayName,
        bio, avatar_media_id AS avatarMediaId, is_private AS isPrivate, is_suspended AS isSuspended
        FROM phone_social_profiles WHERE device_id = ? LIMIT 1]], { deviceId })
end

function Social.profileById(id)
    return MySQL.single.await([[SELECT id, device_id AS deviceId, handle, display_name AS displayName,
        bio, avatar_media_id AS avatarMediaId, is_private AS isPrivate, is_suspended AS isSuspended
        FROM phone_social_profiles WHERE id = ? LIMIT 1]], { id })
end

function Social.createProfile(deviceId, handle, displayName, bio, isPrivate)
    local id = MySQL.insert.await([[INSERT INTO phone_social_profiles
        (device_id, handle, display_name, bio, is_private) VALUES (?, ?, ?, ?, ?)]],
        { deviceId, handle, displayName, bio, isPrivate and 1 or 0 })
    return id and Social.profileById(id) or nil
end

function Social.feed(viewerDeviceId, viewerProfileId, limit, cursor)
    local sql = [[SELECT po.id, po.body, UNIX_TIMESTAMP(po.created_at) AS createdAt,
        pr.id AS authorProfileId, pr.handle, pr.display_name AS displayName, pr.avatar_media_id AS avatarMediaId,
        (SELECT COUNT(*) FROM phone_social_likes l WHERE l.post_id = po.id) AS likeCount,
        (SELECT COUNT(*) FROM phone_social_comments c WHERE c.post_id = po.id AND c.deleted_at IS NULL) AS commentCount,
        EXISTS(SELECT 1 FROM phone_social_likes ml WHERE ml.post_id = po.id AND ml.profile_id = ?) AS liked,
        (po.author_profile_id = ?) AS mine, m.public_url AS mediaUrl, m.mime_type AS mediaMime
        FROM phone_social_posts po JOIN phone_social_profiles pr ON pr.id = po.author_profile_id
        LEFT JOIN phone_media m ON m.id = po.media_id AND m.deleted_at IS NULL
        WHERE po.deleted_at IS NULL AND pr.is_suspended = 0
          AND NOT EXISTS(SELECT 1 FROM phone_blocks b WHERE
            (b.blocker_device_id = ? AND b.blocked_device_id = pr.device_id) OR
            (b.blocker_device_id = pr.device_id AND b.blocked_device_id = ?))
          AND (pr.is_private = 0 OR pr.id = ? OR EXISTS(SELECT 1 FROM phone_social_follows f
            WHERE f.follower_profile_id = ? AND f.following_profile_id = pr.id))]]
    local params = { viewerProfileId, viewerProfileId, viewerDeviceId, viewerDeviceId, viewerProfileId, viewerProfileId }
    if cursor then sql = sql .. ' AND po.id < ?'; params[#params + 1] = cursor end
    sql = sql .. ' ORDER BY po.id DESC LIMIT ?'; params[#params + 1] = limit
    return MySQL.query.await(sql, params) or {}
end

function Social.insertPost(profileId, body, requestId, mediaId)
    local ok, id = pcall(MySQL.insert.await, [[INSERT INTO phone_social_posts
        (author_profile_id, body, media_id, client_request_id) VALUES (?, ?, NULLIF(?, 0), ?)]], { profileId, body, mediaId or 0, requestId })
    if ok then return MySQL.single.await('SELECT id, body, UNIX_TIMESTAMP(created_at) AS createdAt FROM phone_social_posts WHERE id = ?', { id }), false end
    local existing = MySQL.single.await([[SELECT id, body, UNIX_TIMESTAMP(created_at) AS createdAt
        FROM phone_social_posts WHERE author_profile_id = ? AND client_request_id = ?]], { profileId, requestId })
    return existing, existing ~= nil
end

function Social.postInternal(id)
    return MySQL.single.await([[SELECT po.id, po.author_profile_id AS authorProfileId, pr.device_id AS authorDeviceId,
        pr.is_private AS authorIsPrivate,
        po.body, po.deleted_at AS deletedAt FROM phone_social_posts po
        JOIN phone_social_profiles pr ON pr.id = po.author_profile_id WHERE po.id = ?]], { id })
end

function Social.isFollowing(followerProfileId, followingProfileId)
    if not followerProfileId then return false end
    return MySQL.scalar.await([[SELECT EXISTS(SELECT 1 FROM phone_social_follows
        WHERE follower_profile_id = ? AND following_profile_id = ?)]],
        { followerProfileId, followingProfileId }) == 1
end

function Social.deletePost(profileId, postId)
    return MySQL.update.await([[UPDATE phone_social_posts SET deleted_at = CURRENT_TIMESTAMP
        WHERE id = ? AND author_profile_id = ? AND deleted_at IS NULL]], { postId, profileId }) > 0
end

function Social.setLike(profileId, postId, liked)
    if liked then
        MySQL.insert.await('INSERT IGNORE INTO phone_social_likes (post_id, profile_id) VALUES (?, ?)', { postId, profileId })
    else
        MySQL.update.await('DELETE FROM phone_social_likes WHERE post_id = ? AND profile_id = ?', { postId, profileId })
    end
    return MySQL.scalar.await('SELECT COUNT(*) FROM phone_social_likes WHERE post_id = ?', { postId }) or 0
end

function Social.setFollow(followerId, followingId, following)
    if following then
        MySQL.insert.await('INSERT IGNORE INTO phone_social_follows (follower_profile_id, following_profile_id) VALUES (?, ?)', { followerId, followingId })
    else
        MySQL.update.await('DELETE FROM phone_social_follows WHERE follower_profile_id = ? AND following_profile_id = ?', { followerId, followingId })
    end
end

function Social.insertComment(postId, profileId, body, requestId)
    local ok, id = pcall(MySQL.insert.await, [[INSERT INTO phone_social_comments
        (post_id, author_profile_id, body, client_request_id) VALUES (?, ?, ?, ?)]], { postId, profileId, body, requestId })
    if ok then return MySQL.single.await('SELECT id, post_id AS postId, body, UNIX_TIMESTAMP(created_at) AS createdAt FROM phone_social_comments WHERE id = ?', { id }) end
    return MySQL.single.await([[SELECT id, post_id AS postId, body, UNIX_TIMESTAMP(created_at) AS createdAt
        FROM phone_social_comments WHERE author_profile_id = ? AND client_request_id = ?]], { profileId, requestId })
end

function Social.comments(postId, viewerDeviceId, limit, cursor)
    local sql = [[SELECT c.id, c.post_id AS postId, c.body, UNIX_TIMESTAMP(c.created_at) AS createdAt,
        p.id AS authorProfileId, p.handle, p.display_name AS displayName
        FROM phone_social_comments c JOIN phone_social_profiles p ON p.id = c.author_profile_id
        WHERE c.post_id = ? AND c.deleted_at IS NULL AND p.is_suspended = 0
        AND NOT EXISTS(SELECT 1 FROM phone_blocks b WHERE
          (b.blocker_device_id = ? AND b.blocked_device_id = p.device_id) OR
          (b.blocker_device_id = p.device_id AND b.blocked_device_id = ?))]]
    local params = { postId, viewerDeviceId, viewerDeviceId }
    if cursor then sql = sql .. ' AND c.id < ?'; params[#params + 1] = cursor end
    sql = sql .. ' ORDER BY c.id DESC LIMIT ?'; params[#params + 1] = limit
    return MySQL.query.await(sql, params) or {}
end

function Social.deleteComment(profileId, commentId)
    return MySQL.update.await([[UPDATE phone_social_comments SET deleted_at = CURRENT_TIMESTAMP
        WHERE id = ? AND author_profile_id = ? AND deleted_at IS NULL]], { commentId, profileId }) > 0
end

function Social.commentInternal(id)
    return MySQL.single.await([[SELECT c.id, c.post_id AS postId, c.body, p.device_id AS authorDeviceId
        FROM phone_social_comments c JOIN phone_social_profiles p ON p.id = c.author_profile_id WHERE c.id = ?]], { id })
end

function Social.removeFollowsBetween(profileA, profileB)
    MySQL.update.await([[DELETE FROM phone_social_follows WHERE
        (follower_profile_id = ? AND following_profile_id = ?) OR
        (follower_profile_id = ? AND following_profile_id = ?)]], { profileA, profileB, profileB, profileA })
end

function Social.setSuspended(profileId, suspended)
    return MySQL.update.await('UPDATE phone_social_profiles SET is_suspended = ? WHERE id = ?', { suspended and 1 or 0, profileId }) > 0
end


function Social.hidePostByModerator(postId)
    return MySQL.update.await([[UPDATE phone_social_posts SET deleted_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL]], { postId }) > 0
end

function Social.hideCommentByModerator(commentId)
    return MySQL.update.await([[UPDATE phone_social_comments SET deleted_at = CURRENT_TIMESTAMP
        WHERE id = ? AND deleted_at IS NULL]], { commentId }) > 0
end
