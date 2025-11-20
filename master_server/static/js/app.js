const { createApp, ref } = Vue;

createApp({
    delimiters: ['[[', ']]'],
    
    setup() {
        const file = ref(null);
        const isDragging = ref(false);
        const status = ref('idle');
        const resultText = ref('');
        const showTimestamps = ref(false);
        const resultSegments = ref([]);
        const errorMessage = ref('');
        const workers = ref([]);
        const showAddWorker = ref(false);
        const newWorkerUrl = ref('');
        const allWorkers = ref([]);
        const history = ref([]);
        const stats = ref({ workers: { online: 0, busy: 0, total: 0 }, jobs: { processing: 0, completed: 0, failed: 0 } });
        const selectedJob = ref(null);
        const showJobDetail = ref(false);
        const currentJobId = ref(null);
        const currentJobStatus = ref('idle');
        const usePurifier = ref(true);
        const purifierCompleted = ref(false);
        const purifierBypassed = ref(false);
        let pollInterval = null;

        // Purifier設定をAPI経由で保存
        const savePurifierPreference = async (value) => {
            try {
                await fetch('/preferences/purifier', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ usePurifier: value })
                });
            } catch (e) {
                console.error('Failed to save purifier preference:', e);
            }
        };

        // Purifier設定をAPIから取得
        const loadPurifierPreference = async () => {
            try {
                const response = await fetch('/preferences/purifier');
                const data = await response.json();
                usePurifier.value = data.usePurifier;
            } catch (e) {
                console.error('Failed to load purifier preference:', e);
            }
        };

        // オンラインワーカーを取得
        const fetchWorkers = async () => {
            try {
                const response = await fetch('/workers');
                const data = await response.json();
                workers.value = data.workers.map(w => ({
                    id: w.id,
                    url: w.url,
                    progress: 0,
                    status: w.status || 'online',
                    current_chunk: w.current_chunk || null,
                    last_seen: w.last_seen || null
                }));
                // 全ワーカーリストも取得
                allWorkers.value = data.workers.map(w => w.url);
            } catch (e) {
                console.error('Failed to fetch workers:', e);
                workers.value = [];
                allWorkers.value = [];
            }
        };

        // 統計情報取得
        const fetchStats = async () => {
            try {
                const response = await fetch('/stats');
                const data = await response.json();
                stats.value = data;
            } catch (e) {
                console.error('Failed to fetch stats:', e);
            }
        };

        // ジョブ履歴取得
        const fetchJobs = async () => {
            try {
                const response = await fetch('/jobs');
                const data = await response.json();
                history.value = data.jobs.map(job => ({
                    id: job.job_id,
                    name: job.filename || 'Unknown',
                    status: job.status,
                    created_at: job.created_at,
                    completed_at: job.completed_at,
                    progress: job.progress || 0
                }));
            } catch (e) {
                console.error('Failed to fetch jobs:', e);
            }
        };

        // ジョブ詳細取得
        const fetchJobDetail = async (jobId) => {
            try {
                const response = await fetch(`/jobs/${jobId}`);
                const data = await response.json();
                selectedJob.value = data;
                showJobDetail.value = true;
            } catch (e) {
                console.error('Failed to fetch job detail:', e);
                errorMessage.value = 'ジョブ詳細の取得に失敗しました';
            }
        };

        // Socket.IOセットアップ
        const socket = io();

        socket.on('connect', () => {
            console.log('[socket] connected');
        });

        // ジョブ更新イベント
        socket.on('job_update', (data) => {
            if (!data || !data.status) return;
            const previousStatus = currentJobStatus.value;
            currentJobStatus.value = data.status;
            // 状態別UI反映
            if (data.status === 'purifier_completed') {
                purifierCompleted.value = true;
                status.value = 'cleaning';
                setTimeout(() => { purifierCompleted.value = false; }, 1500);
            } else if (data.status === 'purifier_bypassed') {
                purifierBypassed.value = true;
                status.value = 'cleaning';
                setTimeout(() => { purifierBypassed.value = false; }, 1200);
            } else if (data.status === 'purifying') {
                status.value = 'cleaning';
            } else if (['splitting','processing','aggregating'].includes(data.status)) {
                status.value = 'transcribing';
            } else if (data.status === 'completed') {
                status.value = 'idle';
            } else if (data.status === 'failed') {
                status.value = 'idle';
                errorMessage.value = data.error || 'ジョブが失敗しました';
            }
            // チャンク進捗更新
            if (data.chunks && data.chunks.length > 0) {
                const completedChunks = data.chunks.filter(c => c.status === 'completed').length;
                const totalChunks = data.chunks.length;
                workers.value.forEach(w => {
                    const processingChunk = data.chunks.find(c => c.status === 'processing' && c.worker_url === w.url);
                    if (processingChunk) {
                        w.status = 'busy';
                        w.current_chunk = processingChunk.chunk_id.split('_').pop();
                        w.progress = Math.min(95, (completedChunks / totalChunks) * 100 + Math.random() * 10);
                    } else {
                        w.status = 'online';
                        w.current_chunk = null;
                        w.progress = (completedChunks / totalChunks) * 100;
                    }
                });
            }
            // 完了時結果表示
            if (data.status === 'completed' && data.result && data.result.text) {
                resultSegments.value = data.result.segments || [];
                finishProcess(data.result.text);
            }
        });

        const stopPolling = () => {}; // 互換のため残すが未使用

        const copySegments = () => {
            if (!resultSegments.value || resultSegments.value.length === 0) return;
            const text = resultSegments.value
                .map(s => `${s.start} → ${s.end}  ${s.text}`)
                .join('\n');
            navigator.clipboard.writeText(text);
        };

        const copySelectedJobText = () => {
            if (!selectedJob.value || !selectedJob.value.result) return;
            const text = selectedJob.value.result.text || '';
            navigator.clipboard.writeText(text);
        };

        const copySelectedJobSegments = () => {
            if (!selectedJob.value || !selectedJob.value.result || !selectedJob.value.result.segments) return;
            const text = selectedJob.value.result.segments
                .map(s => `${s.start} → ${s.end}  ${s.text}`)
                .join('\n');
            navigator.clipboard.writeText(text);
        };

        const handleDrop = (e) => {
            isDragging.value = false;
            const droppedFiles = e.dataTransfer.files;
            if (droppedFiles.length > 0) file.value = droppedFiles[0];
        };

        const handleFileSelect = (e) => {
            if (e.target.files.length > 0) file.value = e.target.files[0];
        };

        const startProcess = async () => {
            if (!file.value) return;
            resultText.value = '';
            
            if (workers.value.length === 0) {
                errorMessage.value = 'Workerがいません！\n\nWorker Nodeを起動してから再度お試しください。';
                return;
            }
            
            const formData = new FormData();
            formData.append('file', file.value);
            // 初期ステータス（実際のフェーズはサーバからのイベントで更新）
            status.value = usePurifier.value ? 'cleaning' : 'transcribing';
            currentJobStatus.value = usePurifier.value ? 'purifying' : 'splitting';

            try {
                const response = await fetch('/submit', {
                    method: 'POST',
                    body: formData
                });
                if (!response.ok) {
                    throw new Error('Server returned error: ' + response.status);
                }
                const data = await response.json();
                if (data.status === 'error') {
                    throw new Error(data.message || 'Unknown error');
                }
                if (data.job_id) {
                    currentJobId.value = data.job_id;
                    socket.emit('subscribe_job', { job_id: data.job_id });
                } else {
                    throw new Error('job_idが取得できませんでした');
                }
                // 結果は非同期でjob_update(completed)イベントから受信するためここでは処理しない
            } catch (e) {
                errorMessage.value = 'エラーが発生しました\n\n' + e.message;
                status.value = 'idle';
                currentJobId.value = null;
                currentJobStatus.value = 'idle';
                workers.value.forEach(w => w.progress = 0);
            }
        };

        const finishProcess = async (text) => {
            await new Promise(r => setTimeout(r, 500));
            stopPolling();
            status.value = 'idle';
            currentJobId.value = null;
            currentJobStatus.value = 'idle';
            workers.value.forEach(w => w.progress = 0);
            
            for (let i = 0; i < text.length; i++) {
                resultText.value += text[i];
                await new Promise(r => setTimeout(r, 30));
            }
        };

        const copyText = () => {
            navigator.clipboard.writeText(resultText.value);
        };

        const toggleTimestamps = () => {
            showTimestamps.value = !showTimestamps.value;
        };

        const addWorker = async () => {
            if (!newWorkerUrl.value.trim()) {
                errorMessage.value = 'Worker URLを入力してください';
                return;
            }

            try {
                const response = await fetch('/workers/add', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ url: newWorkerUrl.value })
                });

                const data = await response.json();

                if (!response.ok) {
                    throw new Error(data.error || '追加に失敗しました');
                }

                newWorkerUrl.value = '';
                showAddWorker.value = false;
                await fetchWorkers();
            } catch (e) {
                errorMessage.value = 'ワーカー追加エラー\n\n' + e.message;
            }
        };

        const removeWorker = async (workerUrl) => {
            if (!confirm(`${workerUrl} を削除しますか？`)) {
                return;
            }

            try {
                const response = await fetch('/workers/remove', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ url: workerUrl })
                });

                const data = await response.json();

                if (!response.ok) {
                    throw new Error(data.error || '削除に失敗しました');
                }

                await fetchWorkers();
            } catch (e) {
                errorMessage.value = 'ワーカー削除エラー\n\n' + e.message;
            }
        };

        const getStatusBadgeClass = (status) => {
            const classes = {
                'created': 'bg-gray-100 text-gray-600',
                'purifying': 'bg-blue-100 text-blue-600',
                'splitting': 'bg-yellow-100 text-yellow-600',
                'processing': 'bg-purple-100 text-purple-600',
                'aggregating': 'bg-indigo-100 text-indigo-600',
                'completed': 'bg-green-100 text-green-600',
                'failed': 'bg-red-100 text-red-600'
            };
            return classes[status] || 'bg-gray-100 text-gray-600';
        };

        const formatTime = (timestamp) => {
            if (!timestamp) return 'N/A';
            const date = new Date(timestamp);
            const now = new Date();
            const diff = Math.floor((now - date) / 1000);
            
            if (diff < 60) return `${diff}秒前`;
            if (diff < 3600) return `${Math.floor(diff / 60)}分前`;
            if (diff < 86400) return `${Math.floor(diff / 3600)}時間前`;
            return `${Math.floor(diff / 86400)}日前`;
        };

        const getWorkerStatusIcon = (workerStatus) => {
            const icons = {
                'online': 'check_circle',
                'busy': 'hourglass_empty',
                'offline': 'cancel'
            };
            return icons[workerStatus] || 'help';
        };

        const getWorkerStatusColor = (workerStatus) => {
            const colors = {
                'online': 'text-green-500',
                'busy': 'text-yellow-500',
                'offline': 'text-red-500'
            };
            return colors[workerStatus] || 'text-gray-500';
        };

        // 初期ロード時にデータ取得 (ポーリングは廃止)
        fetchWorkers();
        fetchStats();
        fetchJobs();
        loadPurifierPreference();

        // usePurifierの変更を監視
        Vue.watch(() => usePurifier.value, (newValue) => {
            savePurifierPreference(newValue);
        });

        return {
            file,
            isDragging,
            status,
            resultText,
            showTimestamps,
            resultSegments,
            errorMessage,
            workers,
            showAddWorker,
            newWorkerUrl,
            allWorkers,
            history,
            stats,
            selectedJob,
            showJobDetail,
            currentJobStatus,
            usePurifier,
            purifierCompleted,
            purifierBypassed,
            handleDrop,
            handleFileSelect,
            startProcess,
            copyText,
            copySegments,
            copySelectedJobText,
            copySelectedJobSegments,
            toggleTimestamps,
            addWorker,
            removeWorker,
            fetchJobDetail,
            getStatusBadgeClass,
            formatTime,
            getWorkerStatusIcon,
            getWorkerStatusColor
        };
    }
}).mount('#app');
