use v6.d.PREVIEW;
use Red::Model;
use Red::AttrColumn;
use Red::Column;
use Red::Utils;
use Red::ResultSet;
use Red::DefaultResultSet;
use Red::AttrReferencedBy;
use Red::AttrQuery;
use Red::Filter;

class MetamodelX::Model is Metamodel::ClassHOW {
    has %!columns{Attribute};
    has %!attr-to-column;
    has %.dirty-cols is rw;
    has $.rs-class;

    method table(Mu \type) { camel-to-snake-case type.^name }
    method rs-class-name(Mu \type) { "{type.^name}::ResultSet" }
    method columns(|) is rw {
        %!columns
    }

    method id(Mu \type) {
        %!columns.keys.grep(*.column.id).list
    }

    method id-values(Red::Model:D $model) {
        self.id($model).map({ .get_value: $model }).list
    }

    method attr-to-column(|) is rw {
        %!attr-to-column
    }

    method compose(Mu \type) {
        if $.rs-class === Any {
            my $rs-class-name = $.rs-class-name(type);
            if try ::($rs-class-name) !~~ Nil {
                $!rs-class = ::($rs-class-name)
            } else {
                $!rs-class := Metamodel::ClassHOW.new_type: :name($rs-class-name);
                $!rs-class.^add_parent: Red::DefaultResultSet;
                $!rs-class.^add_method: "of", method { type }
                $!rs-class.^compose;
                type.WHO<ResultSet> := $!rs-class
            }
        }
        die "{$.rs-class.^name} should do the Red::ResultSet role" unless $.rs-class ~~ Red::ResultSet;
        self.add_role: type, Red::Model;
        type.^compose-columns;
        self.add_role: type, role :: {
            method TWEAK(|) {
                self.^set-dirty: self.^columns
            }
        }
        self.Metamodel::ClassHOW::compose(type);
        for type.^attributes -> $attr {
            %!attr-to-column{$attr.name} = $attr.column.name if $attr ~~ Red::AttrColumn:D;
        }
    }

    method add-column(Red::Model:U \type, Red::AttrColumn $attr) {
        %!columns ∪= $attr;
        my $name = $attr.name.substr: 2;
        type.^add_multi_method: $name, method (Red::Model:U:) {
            $attr.column
        }
        if $attr.has_accessor {
            if $attr.rw {
                type.^add_multi_method: $name, method () is rw {
                    my \obj = self;
                    Proxy.new:
                        FETCH => method {
                            $attr.get_value: obj
                        },
                        STORE => method (\value) {
                            return if value === $attr.get_value: obj;
                            obj.^set-dirty: $attr;
                            $attr.set_value: obj, value;
                        }
                    ;
                }
            } else {
                type.^add_multi_method: $name, method () {
                    $attr.get_value: self
                }
            }
        }
    }

    method compose-columns(Red::Model:U \type) {
        for type.^attributes.grep: Red::AttrColumn -> Red::AttrColumn $attr {
            type.^add-column: $attr
        }
    }

    method set-dirty($, $attr) {
        self.dirty-cols ∪= $attr;
    }
    method is-dirty(Any:D \obj) { so self.dirty-cols }
    method clean-up(Any:D \obj) { self.dirty-cols = set() }
    method dirty-columns(|)     { self.dirty-cols }
    method rs($)                { $.rs-class.new }
}

my package EXPORTHOW {
    package DECLARE {
        constant model = MetamodelX::Model;
    }
}
my package EXPORT::DEFAULT {
    use Red::Traits;
    for Red::Traits::EXPORT::ALL::.keys -> $key {
        OUR::{$key} := Red::Traits::EXPORT::ALL::{ $key }
    }
}
