# \Engine\Source\Runtime\CoreUObject\Public\UObject\ObjectMacros.h
import std / [bitops, macrocache, macros, genasts, tables, strformat, sequtils, strutils]

type 
  Flag* = object
    name*: string
    value*: uint64
    description*: string
    combined*: bool
  Flags* = seq[Flag]
  FlagsTable* = Table[string, Flags]

proc f(name: string, value: uint64, description: string): Flag =
  Flag(name: name, value: value, description: description, combined: countSetBits(value) > 1)

converter FlagToU64*(f: Flag): uint64 = f.value

proc `or`*(a: Flag, b: Flag): uint64 =
  a.value or b.value

var flagsTable*:FlagsTable

proc decodeEnumValue*(flagType:string, flagValue:int): Flags =
  if not flagsTable.hasKey(flagType):
    return

  let fv:uint64 = cast[uint64](flagValue)

  #echo &" found {flagType} {flagValue}"
  let flags = flagsTable[flagType]
  # check if there's an exact match
  var res = flags.filterIt(fv == it.value)
  if res.len > 0:
    # we might have more than one match due to aliases!
    echo "-- Found multiple exact matches"
    var names = res.mapIt(it.name).join(" or ")
    var desc = res.mapIt(it.description).join("\nor\n")
    result.add f(names, res[0].value, desc)
    return
  
  # decode the value
  var resultValue:uint64
  for f in flags:
    if not f.combined and ((fv and f.value) > 0):
      result.add f
      resultValue = resultValue or f.value

  doAssert(fv == resultValue, &"Could not decode {flagType} {fv:#X = } != {resultValue:#X = }")


macro createFlags(flagsData: varargs[untyped]): untyped =
  let flagsName = flagsData[0]

  result = nnkStmtList.newTree()
  let declflags = genAst(flagsName):
    var flagsName*: Flags
  result.add declflags

  var stmts = nnkStmtList.newTree()
  var b = nnkBlockStmt.newTree(newEmptyNode(), stmts)
  for it in flagsData[1..^1]:
    let fl = genAst(flagsName, id = it[0], idStr = newLit(it[0].strVal), value = it[1], desc = it[2]):
      let id = f(idStr, value, desc)
      flagsName.add id
    fl.copyChildrenTo(stmts)
  result.add b

  let insertFlags = genAst(flagsName, flagsNameStr = newLit(flagsName.strVal)):
    flagsTable[flagsNameStr] = flagsName
  result.add insertFlags

createFlags(EPackageFlags,
  (PKG_None,                       0x00000000u64, "No flags"),
  (PKG_NewlyCreated,               0x00000001u64, "Newly created package, not saved yet. In editor only."),
  (PKG_ClientOptional,             0x00000002u64, "Purely optional for clients."),
  (PKG_ServerSideOnly,             0x00000004u64, "Only needed on the server side."),
  (PKG_CompiledIn,                 0x00000010u64, "This package is from \"compiled in\" classes."),
  (PKG_ForDiffing,                 0x00000020u64, "This package was loaded just for the purposes of diffing"),
  (PKG_EditorOnly,                 0x00000040u64, "This is editor-only package (for example: editor module script package)"),
  (PKG_Developer,                  0x00000080u64, "Developer module"),
  (PKG_UncookedOnly,               0x00000100u64, "Loaded only in uncooked builds (i.e. runtime in editor)"),
  (PKG_Cooked,                     0x00000200u64, "Package is cooked"),
  (PKG_ContainsNoAsset,            0x00000400u64, "Package doesn't contain any asset object (although asset tags can be present)"),
  (PKG_ExternallyReferenceable,    0x00000800u64, "(Not Implemented) Objects in this package can be referenced in a different plugin or mount point (i.e /Game -> /Engine)"),
  #PKG_Unused           0x00001000u64,
  (PKG_UnversionedProperties,      0x00002000u64, "Uses unversioned property serialization instead of versioned tagged property serialization"),
  (PKG_ContainsMapData,            0x00004000u64, "Contains map data (UObjects only referenced by a single ULevel) but is stored in a different package"),
  (PKG_IsSaving,                   0x00008000u64, "Temporarily set on a package while it is being saved."),
  (PKG_Compiling,                  0x00010000u64, "Package is currently being compiled"),
  (PKG_ContainsMap,                0x00020000u64, "Set if the package contains a ULevel/ UWorld object"),
  (PKG_RequiresLocalizationGather, 0x00040000u64, "Set if the package contains any data to be gathered by localization"),
  #PKG_Unused           0x0008000064,
  (PKG_PlayInEditor,               0x00100000u64, "Set if the package was created for the purpose of PIE"),
  (PKG_ContainsScript,             0x00200000u64, "Package is allowed to contain UClass objects"),
  (PKG_DisallowExport,             0x00400000u64, "Editor should not export asset in this package"),
  #PKG_Unused           0x00800000u64,
  #PKG_Unused           0x01000000u64,
  #PKG_Unused           0x02000000u64,
  #PKG_Unused           0x04000000u64,
  #PKG_Unused           0x08000000u64,
  (PKG_DynamicImports,             0x10000000u64, "This package should resolve dynamic imports from its export at runtime."),
  (PKG_RuntimeGenerated,           0x20000000u64, "This package contains elements that are runtime generated, and may not follow standard loading order rules"),
  (PKG_ReloadingForCooker,         0x40000000u64, "This package is reloading in the cooker, try to avoid getting data we will never need. We won't save this package."),
  (PKG_FilterEditorOnly,           0x80000000u64, "Package has editor-only data filtered out"),

  (PKG_TransientFlags,             PKG_NewlyCreated or PKG_IsSaving or PKG_ReloadingForCooker, "PKG_NewlyCreated or PKG_IsSaving or PKG_ReloadingForCooker: Transient Flags are cleared when serializing to or from PackageFileSummary"),
  (PKG_InMemoryOnly,               PKG_CompiledIn or PKG_NewlyCreated, "PKG_CompiledIn or PKG_NewlyCreated: Flag mask that indicates if this package is a package that exists in memory only.")
)

# Flags describing a class.
createFlags(EClassFlags,
  (CLASS_None,                            0x00000000u64, "No Flags"),
  (CLASS_Abstract,                        0x00000001u64, "Class is abstract and can't be instantiated directly."),
  (CLASS_DefaultConfig,                   0x00000002u64, "Save object configuration only to Default INIs, never to local INIs. Must be combined with CLASS_Config"),
  (CLASS_Config,                          0x00000004u64, "Load object configuration at construction time."),
  (CLASS_Transient,                       0x00000008u64, "This object type can't be saved; null it out at save time."),
  (CLASS_Optional,                        0x00000010u64, "This object type may not be available in certain context. (i.e. game runtime or in certain configuration). Optional class data is saved separately to other object types. (i.e. might use sidecar files)"),
  (CLASS_MatchedSerializers,              0x00000020u64, ""),
  (CLASS_ProjectUserConfig,               0x00000040u64, "Indicates that the config settings for this class will be saved to Project/User*.ini (similar to CLASS_GlobalUserConfig)"),
  (CLASS_Native,                          0x00000080u64, "Class is a native class - native interfaces will have CLASS_Native set, but not RF_MarkAsNative"),
  (CLASS_NoExport,                        0x00000100u64, "Don't export to C++ header."),
  (CLASS_NotPlaceable,                    0x00000200u64, "Do not allow users to create in the editor."),
  (CLASS_PerObjectConfig,                 0x00000400u64, "Handle object configuration on a per-object basis, rather than per-class."),
  (CLASS_ReplicationDataIsSetUp,          0x00000800u64, "Whether SetUpRuntimeReplicationData still needs to be called for this class"),
  (CLASS_EditInlineNew,                   0x00001000u64, "Class can be constructed from editinline New button."),
  (CLASS_CollapseCategories,              0x00002000u64, "Display properties in the editor without using categories."),
  (CLASS_Interface,                       0x00004000u64, "Class is an interface"),
  (CLASS_CustomConstructor,               0x00008000u64, "Do not export a constructor for this class, assuming it is in the cpptext"),
  (CLASS_Const,                           0x00010000u64, "All properties and functions in this class are const and should be exported as const"),
  (CLASS_NeedsDeferredDependencyLoading,  0x00020000u64, "Class flag indicating objects of this class need deferred dependency loading"),
  (CLASS_CompiledFromBlueprint,           0x00040000u64, "Indicates that the class was created from blueprint source material"),
  (CLASS_MinimalAPI,                      0x00080000u64, "Indicates that only the bare minimum bits of this class should be DLL exported/imported"),
  (CLASS_RequiredAPI,                     0x00100000u64, "Indicates this class must be DLL exported/imported (along with all of it's members)"),
  (CLASS_DefaultToInstanced,              0x00200000u64, "Indicates that references to this class default to instanced. Used to be subclasses of UComponent, but now can be any UObject"),
  (CLASS_TokenStreamAssembled,            0x00400000u64, "Indicates that the parent token stream has been merged with ours."),
  (CLASS_HasInstancedReference,           0x00800000u64, "Class has component properties."),
  (CLASS_Hidden,                          0x01000000u64, "Don't show this class in the editor class browser or edit inline new menus."),
  (CLASS_Deprecated,                      0x02000000u64, "Don't save objects of this class when serializing"),
  (CLASS_HideDropDown,                    0x04000000u64, "Class not shown in editor drop down for class selection"),
  (CLASS_GlobalUserConfig,                0x08000000u64, "Class settings are saved to <AppData>/..../Blah.ini (as opposed to CLASS_DefaultConfig)"),
  (CLASS_Intrinsic,                       0x10000000u64, "Class was declared directly in C++ and has no boilerplate generated by UnrealHeaderTool"),
  (CLASS_Constructed,                     0x20000000u64, "Class has already been constructed (maybe in a previous DLL version before hot-reload)."),
  (CLASS_ConfigDoNotCheckDefaults,        0x40000000u64, "Indicates that object configuration will not check against ini base/defaults when serialized"),
  (CLASS_NewerVersionExists,              0x80000000u64, "Class has been consigned to oblivion as part of a blueprint recompile, and a newer version currently exists."),

  (CLASS_Inherit, CLASS_Transient or CLASS_Optional or CLASS_DefaultConfig or CLASS_Config or CLASS_PerObjectConfig or CLASS_ConfigDoNotCheckDefaults or CLASS_NotPlaceable or
    CLASS_Const or CLASS_HasInstancedReference or CLASS_Deprecated or CLASS_DefaultToInstanced or CLASS_GlobalUserConfig or CLASS_ProjectUserConfig or CLASS_NeedsDeferredDependencyLoading,
    "Flags to inherit from base class"),

  (CLASS_RecompilerClear, CLASS_Inherit or CLASS_Abstract or CLASS_NoExport or CLASS_Native or CLASS_Intrinsic or CLASS_TokenStreamAssembled,
    "These flags will be cleared by the compiler when the class is parsed during script compilation"),

  (CLASS_ShouldNeverBeLoaded, CLASS_Native or CLASS_Optional or CLASS_Intrinsic or CLASS_TokenStreamAssembled,
    "These flags will be cleared by the compiler when the class is parsed during script compilation"),

  (CLASS_ScriptInherit, CLASS_Inherit or CLASS_EditInlineNew or CLASS_CollapseCategories, "These flags will be inherited from the base class only for non-intrinsic classes"),

  (CLASS_SaveInCompiledInClasses, CLASS_Abstract or CLASS_DefaultConfig or CLASS_GlobalUserConfig or CLASS_ProjectUserConfig or CLASS_Config or CLASS_Transient or 
    CLASS_Optional or CLASS_Native or CLASS_NotPlaceable or CLASS_PerObjectConfig or CLASS_ConfigDoNotCheckDefaults or CLASS_EditInlineNew or CLASS_CollapseCategories or 
    CLASS_Interface or CLASS_DefaultToInstanced or CLASS_HasInstancedReference or CLASS_Hidden or CLASS_Deprecated or CLASS_HideDropDown or CLASS_Intrinsic or 
    CLASS_Const or CLASS_MinimalAPI or CLASS_RequiredAPI or CLASS_MatchedSerializers or CLASS_NeedsDeferredDependencyLoading,
    "This is used as a mask for the flags put into generated code for \"compiled in\" classes.")
)

# Flags used for quickly casting classes of certain types; all class cast flags are inherited
createFlags(EClassCastFlags,
  (CASTCLASS_None,                               0x0000000000000000u64, ""),
  (CASTCLASS_UField,                             0x0000000000000001u64, ""),
  (CASTCLASS_FInt8Property,                      0x0000000000000002u64, ""),
  (CASTCLASS_UEnum,                              0x0000000000000004u64, ""),
  (CASTCLASS_UStruct,                            0x0000000000000008u64, ""),
  (CASTCLASS_UScriptStruct,                      0x0000000000000010u64, ""),
  (CASTCLASS_UClass,                             0x0000000000000020u64, ""),
  (CASTCLASS_FByteProperty,                      0x0000000000000040u64, ""),
  (CASTCLASS_FIntProperty,                       0x0000000000000080u64, ""),
  (CASTCLASS_FFloatProperty,                     0x0000000000000100u64, ""),
  (CASTCLASS_FUInt64Property,                    0x0000000000000200u64, ""),
  (CASTCLASS_FClassProperty,                     0x0000000000000400u64, ""),
  (CASTCLASS_FUInt32Property,                    0x0000000000000800u64, ""),
  (CASTCLASS_FInterfaceProperty,                 0x0000000000001000u64, ""),
  (CASTCLASS_FNameProperty,                      0x0000000000002000u64, ""),
  (CASTCLASS_FStrProperty,                       0x0000000000004000u64, ""),
  (CASTCLASS_FProperty,                          0x0000000000008000u64, ""),
  (CASTCLASS_FObjectProperty,                    0x0000000000010000u64, ""),
  (CASTCLASS_FBoolProperty,                      0x0000000000020000u64, ""),
  (CASTCLASS_FUInt16Property,                    0x0000000000040000u64, ""),
  (CASTCLASS_UFunction,                          0x0000000000080000u64, ""),
  (CASTCLASS_FStructProperty,                    0x0000000000100000u64, ""),
  (CASTCLASS_FArrayProperty,                     0x0000000000200000u64, ""),
  (CASTCLASS_FInt64Property,                     0x0000000000400000u64, ""),
  (CASTCLASS_FDelegateProperty,                  0x0000000000800000u64, ""),
  (CASTCLASS_FNumericProperty,                   0x0000000001000000u64, ""),
  (CASTCLASS_FMulticastDelegateProperty,         0x0000000002000000u64, ""),
  (CASTCLASS_FObjectPropertyBase,                0x0000000004000000u64, ""),
  (CASTCLASS_FWeakObjectProperty,                0x0000000008000000u64, ""),
  (CASTCLASS_FLazyObjectProperty,                0x0000000010000000u64, ""),
  (CASTCLASS_FSoftObjectProperty,                0x0000000020000000u64, ""),
  (CASTCLASS_FTextProperty,                      0x0000000040000000u64, ""),
  (CASTCLASS_FInt16Property,                     0x0000000080000000u64, ""),
  (CASTCLASS_FDoubleProperty,                    0x0000000100000000u64, ""),
  (CASTCLASS_FSoftClassProperty,                 0x0000000200000000u64, ""),
  (CASTCLASS_UPackage,                           0x0000000400000000u64, ""),
  (CASTCLASS_ULevel,                             0x0000000800000000u64, ""),
  (CASTCLASS_AActor,                             0x0000001000000000u64, ""),
  (CASTCLASS_APlayerController,                  0x0000002000000000u64, ""),
  (CASTCLASS_APawn,                              0x0000004000000000u64, ""),
  (CASTCLASS_USceneComponent,                    0x0000008000000000u64, ""),
  (CASTCLASS_UPrimitiveComponent,                0x0000010000000000u64, ""),
  (CASTCLASS_USkinnedMeshComponent,              0x0000020000000000u64, ""),
  (CASTCLASS_USkeletalMeshComponent,             0x0000040000000000u64, ""),
  (CASTCLASS_UBlueprint,                         0x0000080000000000u64, ""),
  (CASTCLASS_UDelegateFunction,                  0x0000100000000000u64, ""),
  (CASTCLASS_UStaticMeshComponent,               0x0000200000000000u64, ""),
  (CASTCLASS_FMapProperty,                       0x0000400000000000u64, ""),
  (CASTCLASS_FSetProperty,                       0x0000800000000000u64, ""),
  (CASTCLASS_FEnumProperty,                      0x0001000000000000u64, ""),
  (CASTCLASS_USparseDelegateFunction,            0x0002000000000000u64, ""),
  (CASTCLASS_FMulticastInlineDelegateProperty,   0x0004000000000000u64, ""),
  (CASTCLASS_FMulticastSparseDelegateProperty,   0x0008000000000000u64, ""),
  (CASTCLASS_FFieldPathProperty,                 0x0010000000000000u64, ""),
  (CASTCLASS_FObjectPtrProperty,                 0x0020000000000000u64, ""),
  (CASTCLASS_FClassPtrProperty,                  0x0040000000000000u64, ""),
  (CASTCLASS_FLargeWorldCoordinatesRealProperty, 0x0080000000000000u64, ""),
  (CASTCLASS_AllFlags,                           0xFFFFFFFFFFFFFFFFu64, "")
)



# Flags associated with each property in a class, overriding the property's default behavior.
# @warning When adding one here, please update ParsePropertyFlags()
createFlags(EPropertyFlags,
  (CPF_None,                           0x0000000000000000u64, ""),
  (CPF_Edit,                           0x0000000000000001u64, "Property is user-settable in the editor."),
  (CPF_ConstParm,                      0x0000000000000002u64, "This is a constant function parameter"),
  (CPF_BlueprintVisible,               0x0000000000000004u64, "This property can be read by blueprint code"),
  (CPF_ExportObject,                   0x0000000000000008u64, "Object can be exported with actor."),
  (CPF_BlueprintReadOnly,              0x0000000000000010u64, "This property cannot be modified by blueprint code"),
  (CPF_Net,                            0x0000000000000020u64, "Property is relevant to network replication."),
  (CPF_EditFixedSize,                  0x0000000000000040u64, "Indicates that elements of an array can be modified, but its size cannot be changed."),
  (CPF_Parm,                           0x0000000000000080u64, "Function/When call parameter."),
  (CPF_OutParm,                        0x0000000000000100u64, "Value is copied out after function call."),
  (CPF_ZeroConstructor,                0x0000000000000200u64, "memset is fine for construction"),
  (CPF_ReturnParm,                     0x0000000000000400u64, "Return value."),
  (CPF_DisableEditOnTemplate,          0x0000000000000800u64, "Disable editing of this property on an archetype/sub-blueprint"),
  #CPF_,                               0x0000000000001000u64,""),
  (CPF_Transient,                      0x0000000000002000u64, "Property is transient: shouldn't be saved or loaded, except for Blueprint CDOs."),
  (CPF_Config,                         0x0000000000004000u64, "Property should be loaded/saved as permanent profile."),
  #CPF_,                               0x0000000000008000u64, ""),
  (CPF_DisableEditOnInstance,          0x0000000000010000u64, "Disable editing on an instance of this class"),
  (CPF_EditConst,                      0x0000000000020000u64, "Property is uneditable in the editor."),
  (CPF_GlobalConfig,                   0x0000000000040000u64, "Load config from base class, not subclass."),
  (CPF_InstancedReference,             0x0000000000080000u64, "Property is a component references."),
  #CPF_,                               0x0000000000100000u64,""),
  (CPF_DuplicateTransient,             0x0000000000200000u64, "Property should always be reset to the default value during any type of duplication (copy/paste, binary duplication, etc.)"),
  #CPF_,                               0x0000000000400000u64 , ""),
  #CPF_,                               0x0000000000800000u64, ""),
  (CPF_SaveGame,                       0x0000000001000000u64, "Property should be serialized for save games, this is only checked for game-specific archives with ArIsSaveGame"),
  (CPF_NoClear,                        0x0000000002000000u64, "Hide clear (and browse) button."),
  #CPF_,                               0x0000000004000000u64, ""),
  (CPF_ReferenceParm,                  0x0000000008000000u64, "Value is passed by reference; CPF_OutParam and CPF_Param should also be set."),
  (CPF_BlueprintAssignable,            0x0000000010000000u64, "MC Delegates only.  Property should be exposed for assigning in blueprint code"),
  (CPF_Deprecated,                     0x0000000020000000u64, "Property is deprecated.  Read it from an archive, but don't save it."),
  (CPF_IsPlainOldData,                 0x0000000040000000u64, "If this is set, then the property can be memcopied instead of CopyCompleteValue / CopySingleValue"),
  (CPF_RepSkip,                        0x0000000080000000u64, "Not replicated. For non replicated properties in replicated structs "),
  (CPF_RepNotify,                      0x0000000100000000u64, "Notify actors when a property is replicated"),
  (CPF_Interp,                         0x0000000200000000u64, "interpolatable property for use with cinematics"),
  (CPF_NonTransactional,               0x0000000400000000u64, "Property isn't transacted"),
  (CPF_EditorOnly,                     0x0000000800000000u64, "Property should only be loaded in the editor"),
  (CPF_NoDestructor,                   0x0000001000000000u64, "No destructor"),
  #CPF_,                               0x0000002000000000u64, ""),
  (CPF_AutoWeak,                       0x0000004000000000u64, "Only used for weak pointers, means the export type is autoweak"),
  (CPF_ContainsInstancedReference,     0x0000008000000000u64, "Property contains component references."),
  (CPF_AssetRegistrySearchable,        0x0000010000000000u64, "asset instances will add properties with this flag to the asset registry automatically"),
  (CPF_SimpleDisplay,                  0x0000020000000000u64, "The property is visible by default in the editor details view"),
  (CPF_AdvancedDisplay,                0x0000040000000000u64, "The property is advanced and not visible by default in the editor details view"),
  (CPF_Protected,                      0x0000080000000000u64, "property is protected from the perspective of script"),
  (CPF_BlueprintCallable,              0x0000100000000000u64, "MC Delegates only.  Property should be exposed for calling in blueprint code"),
  (CPF_BlueprintAuthorityOnly,         0x0000200000000000u64, "MC Delegates only.  This delegate accepts (only in blueprint) only events with BlueprintAuthorityOnly."),
  (CPF_TextExportTransient,            0x0000400000000000u64, "Property shouldn't be exported to text format (e.g. copy/paste)"),
  (CPF_NonPIEDuplicateTransient,       0x0000800000000000u64, "Property should only be copied in PIE"),
  (CPF_ExposeOnSpawn,                  0x0001000000000000u64, "Property is exposed on spawn"),
  (CPF_PersistentInstance,             0x0002000000000000u64, "A object referenced by the property is duplicated like a component. (Each actor should have an own instance.)"),
  (CPF_UObjectWrapper,                 0x0004000000000000u64, "Property was parsed as a wrapper class like TSubclassOf<T>, FScriptInterface etc., rather than a USomething*"),
  (CPF_HasGetValueTypeHash,            0x0008000000000000u64, "This property can generate a meaningful hash value."),
  (CPF_NativeAccessSpecifierPublic,    0x0010000000000000u64, "Public native access specifier"),
  (CPF_NativeAccessSpecifierProtected, 0x0020000000000000u64, "Protected native access specifier"),
  (CPF_NativeAccessSpecifierPrivate,   0x0040000000000000u64, "Private native access specifier"),
  (CPF_SkipSerialization,              0x0080000000000000u64, "Property shouldn't be serialized, can still be exported to text"),

  (CPF_NativeAccessSpecifiers, CPF_NativeAccessSpecifierPublic or CPF_NativeAccessSpecifierProtected or CPF_NativeAccessSpecifierPrivate, "All Native Access Specifier flags"),
  (CPF_ParmFlags,              CPF_Parm or CPF_OutParm or CPF_ReturnParm or CPF_ReferenceParm or CPF_ConstParm, "All parameter flags"),

  (CPF_PropagateToArrayInner, CPF_ExportObject or CPF_PersistentInstance or CPF_InstancedReference or CPF_ContainsInstancedReference or CPF_Config or CPF_EditConst or CPF_Deprecated or CPF_EditorOnly or CPF_AutoWeak or CPF_UObjectWrapper, "Flags that are propagated to properties inside containers"),
  (CPF_PropagateToMapValue,   CPF_ExportObject or CPF_PersistentInstance or CPF_InstancedReference or CPF_ContainsInstancedReference or CPF_Config or CPF_EditConst or CPF_Deprecated or CPF_EditorOnly or CPF_AutoWeak or CPF_UObjectWrapper or CPF_Edit, "Flags that are propagated to properties inside containers"),
  (CPF_PropagateToMapKey,     CPF_ExportObject or CPF_PersistentInstance or CPF_InstancedReference or CPF_ContainsInstancedReference or CPF_Config or CPF_EditConst or CPF_Deprecated or CPF_EditorOnly or CPF_AutoWeak or CPF_UObjectWrapper or CPF_Edit, "Flags that are propagated to properties inside containers"),
  (CPF_PropagateToSetElement, CPF_ExportObject or CPF_PersistentInstance or CPF_InstancedReference or CPF_ContainsInstancedReference or CPF_Config or CPF_EditConst or CPF_Deprecated or CPF_EditorOnly or CPF_AutoWeak or CPF_UObjectWrapper or CPF_Edit, "Flags that are propagated to properties inside containers"),

  (CPF_InterfaceClearMask, CPF_ExportObject or CPF_InstancedReference or CPF_ContainsInstancedReference, "The flags that should never be set on interface properties"),
  (CPF_DevelopmentAssets, CPF_EditorOnly, "All the properties that can be stripped for final release console builds"),
  (CPF_ComputedFlags, CPF_IsPlainOldData or CPF_NoDestructor or CPF_ZeroConstructor or CPF_HasGetValueTypeHash, "All the properties that should never be loaded or saved"),
  (CPF_AllFlags, 0xFFFFFFFFFFFFFFFFu64, "Mask of all property flags")
)


# Extra flags for array properties.
createFlags(EArrayPropertyFlags,
  (None,                     0u64, ""),
  (UsesMemoryImageAllocator, 1u64, "")
)

# Extra flags for map properties.
createFlags(EMapPropertyFlags,
  (None,                     0u64, ""),
  (UsesMemoryImageAllocator, 1u64, "")
)


# Flags describing an object instance
# Do not add new flags unless they truly belong here. There are alternatives.
# if you change any the bit of any of the RF_Load flags, then you will need legacy serialization

createFlags(EObjectFlags,
  (RF_NoFlags,                       0x00000000u64,"No flags, used to avoid a cast"),
  # This first group of flags mostly has to do with what kind of object it is. Other than transient, these are the persistent object flags.
  # The garbage collector also tends to look at these.
  (RF_Public,                        0x00000001u64, "Object is visible outside its package."),
  (RF_Standalone,                    0x00000002u64, "Keep object around for editing even if unreferenced."),
  (RF_MarkAsNative,                  0x00000004u64, "Object (UField) will be marked as native on construction (DO NOT USE THIS FLAG in HasAnyFlags() etc)"),
  (RF_Transactional,                 0x00000008u64, "Object is transactional."),
  (RF_ClassDefaultObject,            0x00000010u64, "This object is its class's default object"),
  (RF_ArchetypeObject,               0x00000020u64, "This object is a template for another object - treat like a class default object"),
  (RF_Transient,                     0x00000040u64, "Don't save object."),

  # This group of flags is primarily concerned with garbage collection.
  (RF_MarkAsRootSet,                 0x00000080u64, "Object will be marked as root set on construction and not be garbage collected, even if unreferenced (DO NOT USE THIS FLAG in HasAnyFlags() etc)"),
  (RF_TagGarbageTemp,                0x00000100u64, "This is a temp user flag for various utilities that need to use the garbage collector. The garbage collector itself does not interpret it."),

  # The group of flags tracks the stages of the lifetime of a UObject
  (RF_NeedInitialization,            0x00000200u64, "This object has not completed its initialization process. Cleared when ~FObjectInitializer completes"),
  (RF_NeedLoad,                      0x00000400u64, "During load, indicates object needs loading."),
  (RF_KeepForCooker,                 0x00000800u64, "Keep this object during garbage collection because it's still being used by the cooker"),
  (RF_NeedPostLoad,                  0x00001000u64, "Object needs to be postloaded."),
  (RF_NeedPostLoadSubobjects,        0x00002000u64, "During load, indicates that the object still needs to instance subobjects and fixup serialized component references"),
  (RF_NewerVersionExists,            0x00004000u64, "Object has been consigned to oblivion due to its owner package being reloaded, and a newer version currently exists"),
  (RF_BeginDestroyed,                0x00008000u64, "BeginDestroy has been called on the object."),
  (RF_FinishDestroyed,               0x00010000u64, "FinishDestroy has been called on the object."),

  # Misc. Flags
  (RF_BeingRegenerated,              0x00020000u64, "Flagged on UObjects that are used to create UClasses (e.g. Blueprints) while they are regenerating their UClass on load (See FLinkerLoad::CreateExport()), as well as UClass objects in the midst of being created"),
  (RF_DefaultSubObject,              0x00040000u64, "Flagged on subobjects that are defaults"),
  (RF_WasLoaded,                     0x00080000u64, "Flagged on UObjects that were loaded"),
  (RF_TextExportTransient,           0x00100000u64, "Do not export object to text form (e.g. copy/paste). Generally used for sub-objects that can be regenerated from data in their parent object."),
  (RF_LoadCompleted,                 0x00200000u64, "Object has been completely serialized by linkerload at least once. DO NOT USE THIS FLAG, It should be replaced with RF_WasLoaded."),
  (RF_InheritableComponentTemplate,  0x00400000u64, "Archetype of the object can be in its super class"),
  (RF_DuplicateTransient,            0x00800000u64, "Object should not be included in any type of duplication (copy/paste, binary duplication, etc.)"),
  (RF_StrongRefOnFrame,              0x01000000u64, "References to this object from persistent function frame are handled as strong ones."),
  (RF_NonPIEDuplicateTransient,      0x02000000u64, "Object should not be included for duplication unless it's being duplicated for a PIE session"),
  (RF_Dynamic,                       0x04000000u64, "UE_DEPRECATED(5.0) Field Only. Dynamic field - doesn't get constructed during static initialization, can be constructed multiple times"),
  (RF_WillBeLoaded,                  0x08000000u64, "This object was constructed during load and will be loaded shortly"),
  (RF_HasExternalPackage,            0x10000000u64, "This object has an external package assigned and should look it up when getting the outermost package"),

  # RF_Garbage and RF_PendingKill are mirrored in EInternalObjectFlags because checking the internal flags is much faster for the Garbage Collector
  # while checking the object flags is much faster outside of it where the Object pointer is already available and most likely cached.
  # RF_PendingKill is mirrored in EInternalObjectFlags because checking the internal flags is much faster for the Garbage Collector
  # while checking the object flags is much faster outside of it where the Object pointer is already available and most likely cached.

  (RF_PendingKill,                   0x20000000u64, "UE_DEPRECATED(5.0) Make sure references to objects are released using one of the existing engine callbacks or use weak object pointers. Objects that are pending destruction (invalid for gameplay but valid objects). This flag is mirrored in EInternalObjectFlags as PendingKill for performance"),
  (RF_Garbage,                       0x40000000u64, "UE_DEPRECATED(5.0) Use MarkAsGarbage and ClearGarbage instead. Garbage from logical point of view and should not be referenced. This flag is mirrored in EInternalObjectFlags as Garbage for performance"),
  (RF_AllocatedInSharedPage,         0x80000000u64, "Allocated from a ref-counted page shared with other UObjects"),

  (RF_AllFlags,                      0xffffffffu64, "Mask for all object flags, used mainly for error checking"),

  (RF_InternalPendingKill, RF_PendingKill, ""),
  (RF_InternalGarbage, RF_Garbage, ""),
  (RF_InternalMirroredFlags, RF_PendingKill or RF_Garbage, ""),

  (RF_Load, RF_Public or RF_Standalone or RF_Transactional or RF_ClassDefaultObject or RF_ArchetypeObject or RF_DefaultSubObject or
    RF_TextExportTransient or RF_InheritableComponentTemplate or RF_DuplicateTransient or RF_NonPIEDuplicateTransient,
    "Flags to load from unreal asset files"),

  (RF_PropagateToSubObjects, RF_Public or RF_ArchetypeObject or RF_Transactional or RF_Transient, "Sub-objects will inherit these flags from their SuperObject")
)



# Objects flags for internal use (GC, low level UObject code)
createFlags(EInternalObjectFlags,
  (None, 0u64, ""),
  (LoaderImport,        uint64(1 shl 20), "Object is ready to be imported by another package during loading"),
  (Garbage,             uint64(1 shl 21), "Garbage from logical point of view and should not be referenced. This flag is mirrored in EObjectFlags as RF_Garbage for performance"),
  (PersistentGarbage,   uint64(1 shl 22), "Same as above but referenced through a persistent reference so it can't be GC'd"),
  (ReachableInCluster,  uint64(1 shl 23), "External reference to object in cluster exists"),
  (ClusterRoot,         uint64(1 shl 24), "Root of a cluster"),
  (Native,              uint64(1 shl 25), "Native (UClass only). "),
  (Async,               uint64(1 shl 26), "Object exists only on a different thread than the game thread."),
  (AsyncLoading,        uint64(1 shl 27), "Object is being asynchronously loaded."),
  (Unreachable,         uint64(1 shl 28), "Object is not reachable on the object graph."),
  (PendingKill,         uint64(1 shl 29), "UE_DEPRECATED(5.0) Use Garbage flag instead. Objects that are pending destruction (invalid for gameplay but valid objects). This flag is mirrored in EObjectFlags as RF_PendingKill for performance"),
  (RootSet,             uint64(1 shl 30), "Object will not be garbage collected, even if unreferenced."),
  (PendingConstruction, uint64(1 shl 31), "Object didn't have its class constructor called yet (only the UObjectBase one to initialize its most basic members)"),

  (GarbageCollectionKeepFlags, Native or Async or AsyncLoading or LoaderImport, ""),
  (MirroredFlags,              Garbage or PendingKill, "Flags mirrored in EObjectFlags"),

  # Make sure this is up to date!
  (AllFlags,                   LoaderImport or Garbage or PersistentGarbage or ReachableInCluster or ClusterRoot or Native or Async or AsyncLoading or Unreachable or PendingKill or RootSet or PendingConstruction, "AllFlags")
)

# Flags describing a UEnum 
createFlags(EEnumFlags,
  (None,               0x00000000u64, ""),
  (Flags,              0x00000001u64, "Whether the UEnum represents a set of flags"),
  (NewerVersionExists, 0x00000002u64, "If set, this UEnum has been replaced by a newer version")
)


# Script.h Function flags.
createFlags(EFunctionFlags,
  (FUNC_None,                   0x00000000u64, ""),
  (FUNC_Final,                  0x00000001u64, "Function is final (prebindable, non-overridable function)."),
  (FUNC_RequiredAPI,            0x00000002u64, "Indicates this function is DLL exported/imported."),
  (FUNC_BlueprintAuthorityOnly, 0x00000004u64, "Function will only run if the object has network authority"),
  (FUNC_BlueprintCosmetic,      0x00000008u64, "Function is cosmetic in nature and should not be invoked on dedicated servers"),
  (FUNC_Unused10,               0x00000010u64, "unused."),
  (FUNC_Unused20,               0x00000020u64, "unused."),
  (FUNC_Net,                    0x00000040u64, "Function is network-replicated."),
  (FUNC_NetReliable,            0x00000080u64, "Function should be sent reliably on the network."),
  (FUNC_NetRequest,             0x00000100u64, "Function is sent to a net service"),
  (FUNC_Exec,                   0x00000200u64, "Executable from command line."),
  (FUNC_Native,                 0x00000400u64, "Native function."),
  (FUNC_Event,                  0x00000800u64, "Event function."),
  (FUNC_NetResponse,            0x00001000u64, "Function response from a net service"),
  (FUNC_Static,                 0x00002000u64, "Static function."),
  (FUNC_NetMulticast,           0x00004000u64, "Function is networked multicast Server -> All Clients"),
  (FUNC_UbergraphFunction,      0x00008000u64, "Function is used as the merge 'ubergraph' for a blueprint, only assigned when using the persistent 'ubergraph' frame"),
  (FUNC_MulticastDelegate,      0x00010000u64, "Function is a multi-cast delegate signature (also requires FUNC_Delegate to be set!)"),
  (FUNC_Public,                 0x00020000u64, "Function is accessible in all classes (if overridden, parameters must remain unchanged)."),
  (FUNC_Private,                0x00040000u64, "Function is accessible only in the class it is defined in (cannot be overridden, but function name may be reused in subclasses.  IOW: if overridden, parameters don't need to match, and Super.Func() cannot be accessed since it's private.)"),
  (FUNC_Protected,              0x00080000u64, "Function is accessible only in the class it is defined in and subclasses (if overridden, parameters much remain unchanged)."),
  (FUNC_Delegate,               0x00100000u64, "Function is delegate signature (either single-cast or multi-cast, depending on whether FUNC_MulticastDelegate is set.)"),
  (FUNC_NetServer,              0x00200000u64, "Function is executed on servers (set by replication code if passes check)"),
  (FUNC_HasOutParms,            0x00400000u64, "function has out (pass by reference) parameters"),
  (FUNC_HasDefaults,            0x00800000u64, "function has structs that contain defaults"),
  (FUNC_NetClient,              0x01000000u64, "function is executed on clients"),
  (FUNC_DLLImport,              0x02000000u64, "function is imported from a DLL"),
  (FUNC_BlueprintCallable,      0x04000000u64, "function can be called from blueprint code"),
  (FUNC_BlueprintEvent,         0x08000000u64, "function can be overridden/implemented from a blueprint"),
  (FUNC_BlueprintPure,          0x10000000u64, "function can be called from blueprint code, and is also pure (produces no side effects). If you set this, you should set FUNC_BlueprintCallable as well."),
  (FUNC_EditorOnly,             0x20000000u64, "function can only be called from an editor scrippt."),
  (FUNC_Const,                  0x40000000u64, "function can be called from blueprint code, and only reads state (never writes state)"),
  (FUNC_NetValidate,            0x80000000u64, "function must supply a _Validate implementation"),
  (FUNC_AllFlags,               0xFFFFFFFFu64, "All flags"),
  # Combinations of flags.
  (FUNC_FuncInherit,            FUNC_Exec or FUNC_Event or FUNC_BlueprintCallable or FUNC_BlueprintEvent or FUNC_BlueprintAuthorityOnly or FUNC_BlueprintCosmetic or FUNC_Const, ""),
  (FUNC_FuncOverrideMatch,      FUNC_Exec or FUNC_Final or FUNC_Static or FUNC_Public or FUNC_Protected or FUNC_Private, ""),
  (FUNC_NetFuncFlags,           FUNC_Net or FUNC_NetReliable or FUNC_NetServer or FUNC_NetClient or FUNC_NetMulticast, ""),
  (FUNC_AccessSpecifiers,       FUNC_Public or FUNC_Private or FUNC_Protected, "")
)

# add new enums by searching for ENUM_CLASS_FLAGS