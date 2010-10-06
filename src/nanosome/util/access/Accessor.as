// @license@
package nanosome.util.access {
	import nanosome.util.ChangedPropertyNode;
	
	import nanosome.util.ILockable;
	import nanosome.util.createInstance;

	import flash.events.IEventDispatcher;
	import flash.utils.describeType;
	import flash.utils.getDefinitionByName;
	import flash.utils.getQualifiedClassName;
	
	/**
	 * <code>Accessor</code> is a wrapper for every instance that allows to easily
	 * manipulate a generic class without taking care of details for this.
	 * 
	 * <p>One feature of <code>Accessor</code> is that it respects the
	 * <code>IPropertiesProxy</code> interface that similar to any other proxy
	 * will receive any property change.</p>
	 * 
	 * <p>Another advantage for using this tool is that its possible to restrict
	 * the objects beeing set to just <code>[Bindable]</code> or <code>[Observable]</code>
	 * properties.</p>
	 * 
	 * <p><code>[Observable]</code> elements are properties that have as metadata
	 * 'Observable' written. In order to compile your code properly you have to add
	 * <code>-compiler.keep-as3-metadata Observable</code> to your <code>mxmlc</code>
	 * or <code>compc</code> arguments.</p>
	 * 
	 * <p>It also takes care that no unnecessary mistakes are beeing done while
	 * accessing the properties with values that don't match the contents of the
	 * target instance. (This is not taken care of properly if you just apply
	 * changes manually)</p>
	 * 
	 * <p>Furthermore changing a list of properties with <code>writeAll</code> or
	 * <code>writeAllByNodes</code> will make use of the <code>ILockable</code>
	 * interface.</p>
	 * 
	 * @example <listening>
	 *   accessFor( {} ).write( {}, "test", 1 ); // returns true because the object is dynamic
	 * </listening>
	 * 
	 * @author Martin Heidegger mh@leichtgewicht.at
	 * @version 1.0
	 * @see ISetterProxy
	 * @see IGetterProxy
	 * @see ILockable
	 */
	public final class Accessor {
		
		/**
		 * Cached qualified name of the ILockable class.
		 * 
		 * @see ILockable
		 */
		protected static const ILOCKABLE: String = getQualifiedClassName( ILockable );
		
		/**
		 * Cached qualified name of the IPropertiesSetterProxy class.
		 * 
		 * @see ISetterProxy
		 */
		protected static const IPROPERTIES_SETTER_PROXY: String = getQualifiedClassName( ISetterProxy );
		
		/**
		 * Cached qualified name of the IPropertiesGetterProxy class.
		 * 
		 * @see IGetterProxy
		 */
		protected static const IPROPERTIES_GETTER_PROXY: String = getQualifiedClassName( IGetterProxy );
		
		/**
		 * Cached qualified name of the IEventDispatcher class to waste less 
		 * performance for the indentification of eventdispatcher instances.
		 * 
		 * @see IEventDispatcher
		 */
		protected static const IEVENT_DISPATCHER: String = getQualifiedClassName( IEventDispatcher );
		
		// Stores modifier intances for each class
		// Maps class name to Modifier instance
		private static var _objectMap: Object /* String -> Modifier */= {};

		/**
		 * Retrieves a <code>Accessor</code> that allows proper access to
		 * variables of a class.
		 * 
		 * <p>If you request a Accessor for a unaccessible class which is eighter
		 * a internal class or not loaded yet you will retrieve the same Accessor
		 * you would also retreive for <code>null</code> Modifications. This
		 * certain Accessor can not access the type informations, which leads to
		 * the inability to respect <code>IPropertiesSetterProxy</code> and the
		 * also the pre-checks of valid types doesn't work.</p>
		 * 
		 * @param object Instance of a class or the class itself for which
		 *            a Modifier should be retrieved
		 * @return Modifier that can handle this class
		 */
		public static function forObject( object: * ): Accessor {
			
			var typeName: String = null;
			if( object ) {
				typeName = getQualifiedClassName( object );
			}
			
			try {
				return _objectMap[ typeName ] || ( _objectMap[ typeName ] = new Accessor( typeName, object ) );
			} catch( e: Error ) {}
			
			// If the instanciation doesn't work, treat the class as
			// completly dynamic!
			return forObject( null );
		}
		
		// Stores the properties which are writable
		private var _writableLookup: Object /* String -> Boolean */;
		
		// Stores the types to the writable properties
		private var _writableTypeLookup: Object /* String -> Class */;
		
		// Lists all readable properties of the class
		private var _normalReadable: Array /* String */;
		
		// List of readables that send out an event
		private var _sendingEventReadable: Array;
		
		private var _readWriteable: Array /* String */;
		
		private var _readWriteableTypeLookup: Object /* String -> Class */;
		
		// Stores the properties that are readable
		private var _readableLookup: Object /* String -> Boolean */;
		
		private var _bindables: Object /* String -> Boolean */;
		
		private var _observables: Object /* String -> Boolean */;
		
		// Flag if the target is dynamic (can contain additional, not-specified properties)
		private var _isDynamic: Boolean = true;
		
		// Flag if the target implements ILockable
		private var _isLockable: Boolean = false;
		
		// Flag if the target is basic object
		private var _isObject : Boolean;
		
		// Flag if the target's class can not be evaluated (null)
		private var _isAnnonymous : Boolean;
		
		// Flag if the target implements ISetterProxy
		private var _isSetterProxy: Boolean;
		
		// Flag if the target implements IGetterProxy
		private var _isGetterProxy: Boolean;
		
		
		/**
		 * Constructs a new <code>Modifier</code> instance.
		 * 
		 * @param typeName name of the type that this modifier should apply to
		 *        <code>null</code> will be treatened as "unaccessable".
		 */
		public function Accessor( typeName: String, object: * ) {
			_isObject = (typeName == "Object");
			_isAnnonymous = !typeName;
			
			// Create lookup tables if they can be created
			if( !_isAnnonymous && !_isObject ) {
				
				var xml: XML;
				
				// This might throw a exception which is catched in the static
				// .forObject method.
				if( object is Class ) {
					try {
						object = createInstance( object );
					} catch( e: Error ) {
						trace( "Warning: '" + typeName + "' can not be properly analyzed, accessFor/Accessor can become slow. Error while instantiation: \n" + e );
					}
				}
				xml = describeType( object );
				
				var interfaces: XMLList = xml.factory.implementsInterface + xml.implementsInterface;
				var variables: XMLList = xml.factory.variable + xml.variable;
				
				_isSetterProxy = interfaces.(@type==IPROPERTIES_SETTER_PROXY).length() > 0;
				_isGetterProxy = interfaces.(@type==IPROPERTIES_GETTER_PROXY).length() > 0;
				_isDynamic = xml["@isDynamic"] == "true" || ( _isSetterProxy && _isGetterProxy );
				_isAnnonymous = false;
				
				var accessors: XMLList = xml.factory.accessor + xml.accessor;
				var name: String;
				
				// Save some time, if its a ISetterProxy, no lookup is required
				if( !_isSetterProxy ) {
					
					_writableLookup = {};
					_writableTypeLookup = {};
					
					// Collect all information about writable properties
					var writeAbles: XMLList = accessors.(@access=="readwrite"||@access=="writeonly") + variables;
					for each( var writeAble: XML in writeAbles ) {
						name = XML( writeAble.@name ).toString();
						_writableLookup[ name ] = true;
						try {
							_writableTypeLookup[ name ] = getDefinitionByName( writeAble.@type );
						} catch( e: Error ) {
							// If the type is not accessible it't not possible to do a verification!
						}
					}
				}
				
				// Save some time, if its a IGetterProxy, no lookup is required
				if( !_isGetterProxy ) {
					
					_readableLookup = {};
					
					// Collect all information about the readable properties
					var readAbles: XMLList = accessors.(@access=="readwrite"||@access=="readonly") + variables;
					for each( var readAble: XML in readAbles ) {
						name = XML( readAble.@name ).toString();
						_readableLookup[ name ] = true;
						
						if( _writableLookup[ name ] ) {
							if( !_readWriteable ) {
								_readWriteable = [];
								_readWriteableTypeLookup = {};
							}
							_readWriteable.push( name );
							try {
								_readWriteableTypeLookup[ name ] = getDefinitionByName( readAble.@type );
							} catch( e: Error ) {
								// If the type is not accessible it't not possible to do a verification!
							}
						}
						
						var bindable: Boolean = readAble.metadata.(@name=="Bindable").length() != 0;
						if( bindable )
							( _bindables || ( _bindables = {} ) )[ name ] = true;
							
						var observable: Boolean = readAble.metadata.(@name=="Observable").length() != 0;
						if( observable )
							( _observables || ( _observables = {} ) )[ name ] = true;
						
						// TODO: Implement a mechanism which tells the system to update certain properties
						// not on-enterframe but rather on some addEventListener event ... man, that would
						// be cool
						
						if( bindable || observable ) {
							( _sendingEventReadable || ( _sendingEventReadable = [] ) ).push( name );
						} else {
							( _normalReadable || ( _normalReadable = [] ) ).push( name );
						}
						
					}
				}
				_isLockable = interfaces.(@type==ILOCKABLE).length() > 0;
			}
		}
		
		/**
		 * Sets a target's property in a passed-in instance to a value.
		 * 
		 * <p>This method will check the passed-in value to its type if possible.
		 * else it will try/catch try to find out if the type matches.</p>
		 * 
		 * <p>If the class implements ISetterProxy, this method will be used
		 * instead of trying to set it manually.</p>
		 * 
		 * @param target Instance that should be written
		 * @param name Name of the property to be set
		 * @param value Value that the property should get
		 * @return <code>true</code> if it could have been set properly
		 * @see ISetterProxy
		 */
		public function write( target: *, name: String, value: * ): Boolean {
			if( _isAnnonymous ) {
				try {
					// Annonymous classes allow 
					var formerValue: * = target[name];
					target[name] = value;
					if( target[name] === value ) {
						return true;
					} else {
						target[name] = formerValue;
						return false;
					}
				} catch( e: Error ){}
				return false;
				
			} else if( _isSetterProxy ) {
				
				return ISetterProxy( target ).write( name, value );
				
			} else if( _writableLookup && _writableLookup[ name ] ) {
				
				const type: * = _writableTypeLookup[ name ];
				if( type ) {
					if( value is type || value == null ) {
						target[ name ] = value;
						return true;
					} else {
						return false;
					}
				} else {
					// If the type can't be verified i.E. when the type was internal
					// then a try/catch is necessary.
					try {
						target[ name ] = value;
						return true;
					} catch( e: Error ) {}
					return false;
				}
				
			} else if( _isDynamic ) {
				
				target[ name ] = value;
				return true;
				
			} else {
				
				return false;
			}
		}
		
		/**
		 * Writes all passed-in properties to the target
		 * 
		 * <p>This method call will automatically lock the target before setting
		 * the first property and unlock it afterwards (if it wasn't locked before).</p>
		 * 
		 * @param target target that should be modified.
		 * @param properties Object that maps property-names to values to be set
		 */
		public function writeAll( target: *, properties: Object ): void {
			var doUnlock: Boolean = false;
			if( _isLockable ) {
				const lockable: ILockable = ILockable( target );
				if( !lockable.locked ) {
					doUnlock = true;
					lockable.lock();
				}
			}
			
			for( var name: String in properties )
				write( target, name, properties[ name ] );
			
			if( doUnlock ) lockable.unlock();
		}
		
		/**
		 * Fills, like <code>writeAll</code>, a instance with all passed
		 * in properties by using a change-property-node-list.
		 * 
		 * @param target target instance that should be written to
		 * @param changed Nodes that were changed
		 * @see IPropertyObserver
		 */
		public function writeAllByNodes( target: *, changed: ChangedPropertyNode ): void {
			var doUnlock: Boolean = false;
			if( _isLockable ) {
				const lockable: ILockable = ILockable( target );
				if( !lockable.locked ) {
					doUnlock = true;
					lockable.lock();
				}
			}
			
			var current: ChangedPropertyNode = changed;
			while( current ) {
				write( target, current.name, current.newValue );
				current = current.next;
			}
			
			if( doUnlock ) lockable.unlock();
		}
		
		public function readMapped( source: *, propertyMap: Object ): Object {
			var result: Object = {};
			for( var name: String in propertyMap ) {
				result[ propertyMap[ name ] || name ] = read( source, name );
			}
			return result;
		}
		
		public function compareWithStorage( source: *, storage: Object ): ChangedPropertyNode {
			
			var field: String;
			var changes: ChangedPropertyNode;
			var lastChange: ChangedPropertyNode;
			var newValue: *;
			var oldValue: *;
			var change: ChangedPropertyNode;
			
			if( _isGetterProxy ) {
				
				return IGetterProxy( source ).compareWithStorage( source, storage );
				
			} else if( _isDynamic ) {
				
				for( field in storage ) {
					try {
						newValue = source[ field ];
					} catch( e: Error ) {
						newValue = null;
					}
					oldValue = storage[ field ];
					if( oldValue != newValue ) {
						if( newValue === null || newValue === undefined ) {
							delete storage[ field ];
						} else {
							storage[ field ] = newValue;
						}
						change = ChangedPropertyNode.POOL.getOrCreate();
						change.name = field;
						change.oldValue = oldValue;
						change.newValue = newValue;
						lastChange = change.addTo( lastChange );
						if( !changes ) {
							changes = lastChange;
						}
					}
				}
				
				for( field in source ) {
					try {
						newValue = source[ field ];
					} catch( e: Error ) {
						newValue = null;
					}
					oldValue = storage[ field ];
					if( oldValue != newValue ) {
						if( newValue === null || newValue === undefined ) {
							delete storage[ field ];
						} else {
							storage[ field ] = newValue;
						}
						change = ChangedPropertyNode.POOL.getOrCreate();
						change.name = field;
						change.oldValue = oldValue;
						change.newValue = newValue;
						lastChange = change.addTo( lastChange );
						if( !changes ) {
							changes = lastChange;
						}
					}
				}
				
			} else {
				
				var i: int = _normalReadable.length;
				while( --i-(-1) ) {
					field = _normalReadable[i];
					
					try {
						newValue = source[ field ];
					} catch( e: Error ) {
						newValue = null;
					}
					oldValue = storage[ field ];
					if( oldValue != newValue ) {
						storage[ field ] = newValue;
						change = ChangedPropertyNode.POOL.getOrCreate();
						change.name = field;
						change.oldValue = oldValue;
						change.newValue = newValue;
						lastChange = change.addTo( lastChange );
						if( !changes ) {
							changes = lastChange;
						}
					}
					
				}
			}
			return changes;
		}
		
		/**
		 * Getter for all properties of an instance.
		 * 
		 * <p>The object returned may be optimized for frequent access. The instance
		 * may only be used for access purposes. <strong>Do not modify the returned
		 * object!</strong></p>
		 * 
		 * <p>If the instance implements <code>IGetterProxy</code> then <code>
		 * instance.getAll</code> will be utilized.</p>
		 * 
		 * @param instance Instance whose properties are requested
		 * @param observableOnly <code>true</code> to list only properties that are
		 *        eigther <code>[Bindable]</code> or <code>[Observable]</code>
		 * @return <code>Object</code> that contains all the properties requested.
		 */
		public function readAll( instance: *, fields: Array = null, observableOnly: Boolean = false ): Object {
			if( fields ) {
				
				throw new Error( "not implemented" );
				
			} else {
				
				if( _isObject ) {
					
					return instance;
					
				} else if( _isGetterProxy ) {
					
					return IGetterProxy( instance ).readAll( fields, observableOnly );
					
				} else {
					
					var result: Object = {};
					var i: int;
					var name: String;
					
					if( _sendingEventReadable ) {
						i = _sendingEventReadable.length;
						
						while( --i-(-1) )
							result[ name = _sendingEventReadable[ i ] ] = instance[ name ];
					}
					
					if( !observableOnly ) {
						
						if( _normalReadable ) {
							i = _normalReadable.length;
							
							while( --i-(-1) )
								result[ name = _normalReadable[ i ] ] = instance[ name ];
						}
						
						if( _isDynamic ) {
							
							// Add still missing properties
							for( name in instance )
								if( !result[ name ] )
									result[ name ] = instance[ name ];
						}
					}
					return result;
				}
			}
		}
		
		/**
		 * Reads a property of a instance.
		 * 
		 * <p>Utilizes <code>IGetterProxy</code> if the instance implements it.</p>
		 * 
		 * @param instance Instance to be accessed.
		 * @param name Name of the property to be read
		 * @return content of the instance's property
		 */
		public function read( instance: *, name: String ): * {
			if( _isGetterProxy ) {
				
				return IGetterProxy( instance ).read( name );
				
			} else if( instance && ( _isDynamic || ( _readableLookup && _readableLookup[ name ] ) ) ) {
				
				return instance[ name ];
				
			} else {
				
				return null;
			}
		}
		
		/**
		 * @param name Property name of instances of this class.
		 * @return <code>true</code> if the property can be read.
		 */
		public function hasReadableProperty( name: String): Boolean {
			return _isDynamic || ( _readableLookup && _readableLookup[ name ] );
		}
		
		/**
		 * @param name Property name of instances of this class.
		 * @return <code>true</code> if the property is supposed to send a event
		 *         on change. (<code>[Bindable]</code> or <code>[Observable]</code>)
		 */
		public function isSendingChangeEvent( name: String ): Boolean {
			return ( _sendingEventReadable && _sendingEventReadable.indexOf( name ) != -1 );
		}
		
		public function get nonEventSendingProperties(): Array {
			return _normalReadable;
		}
		
		public function get observableReadableProperties(): Array {
			return _sendingEventReadable;
		}
		
		public function get properties(): Array {
			return _readWriteable;
		}

		/**
		 * @param name Property name of instances of this class.
		 * @return <code>true</code> if the property can be written or not.
		 */
		public function hasWritableProperty( name: String ): Boolean {
			return _isDynamic || ( _writableLookup && _writableLookup[ name ] );
		}

		public function get hasNonEventSendingProperties(): Boolean {
			return _isDynamic || _normalReadable;
		}
		
		public function get hasBindable() : Boolean {
			return _bindables != null;
		}
		
		public function isBindable( name: String ): Boolean {
			return _bindables ? _bindables[ name ] : false;
		}
		
		public function isObservable( name: String ): Boolean {
			return _observables ? _observables[ name ] : false;
		}
		
		public function get isDynamic(): Boolean {
			return _isDynamic;
		}
		
		public function getPropertyType( name: String ): Class {
			return _readWriteableTypeLookup ? _readWriteableTypeLookup[ name ] : null;
		}
	}
}
