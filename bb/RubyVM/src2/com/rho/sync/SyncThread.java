/*
 *  rhodes
 *
 *  Copyright (C) 2008 Lars Burgess. All rights reserved.
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
package com.rho.sync;

import java.util.Date;

import com.rho.db.PerstLiteAdapter;

/**
 * The Class SyncThread.
 */
public class SyncThread implements Runnable {

	/** The quit. */
	private static boolean quit = false;

	/** The sync. */
	private static String sync = "sync";

	/** The Constant SYNC_WAIT_INTERVAL. */
	private static final long SYNC_WAIT_INTERVAL = 30000L;

	/**
	 * Instantiates a new sync thread.
	 */
	SyncThread() {
		SyncUtil.adapter = PerstLiteAdapter.alloc(null);
		new Thread(this).start();
		System.out.println("SyncEngine is started...");
	}

	/**
	 * Quit.
	 */
	public void quit() {
		synchronized (sync) {
			quit = true;
			sync.notify();
		}
	}

	/*
	 * (non-Javadoc)
	 * 
	 * @see java.lang.Runnable#run()
	 */
	public void run() {
		while (!quit) {
			synchronized (sync) {
				SyncUtil.adapter.initialize(null);
				System.out.println("SyncEngine is awake..."
						+ new Date(System.currentTimeMillis()).toString());

				if (SyncConstants.RUN_TESTS) {
					SyncTest.runAllTests();
				}

				// Thread is simple, process local changes and make sure there
				// are no errors before waiting for SYNC_WAIT_INTERVAL
				if (SyncUtil.processLocalChanges() != SyncConstants.SYNC_PROCESS_CHANGES_OK) {
					System.out
							.println("There was an error processing local changes");
					break;
				}

				try {
					sync.wait(SYNC_WAIT_INTERVAL);
				} catch (InterruptedException e) {
				}
			}
		}
		System.out.println("Shutting down SyncEngine...");
		SyncUtil.adapter.close();
		System.out.println("SyncEngine is shutdown...");
	}

	/**
	 * Wake up sync engine.
	 * 
	 * @return true, if successful
	 */
	public boolean wakeUpSyncEngine() {
		synchronized (sync) {
			if (!quit) {
				sync.notify();
				return true;
			}
			return false;
		}
	}
}