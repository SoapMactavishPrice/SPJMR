({
    decodeInContextOfRef : function(base64Context) {
        if (!base64Context || typeof base64Context !== 'string') return null;
        try {
            var str = base64Context;
            if (str.indexOf('1.') === 0) str = str.substring(2);
            var decoded = JSON.parse(window.atob(str));
            return (decoded && decoded.attributes && decoded.attributes.recordId) || null;
        } catch (e) {
            return null;
        }
    }
})