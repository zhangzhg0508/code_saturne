#!/usr/bin/env python
#============================================================================
#
#     This file is part of the Code_Saturne Kernel, element of the
#     Code_Saturne CFD tool.
#
#     Copyright (C) 2008-2011 EDF S.A., France
#
#     contact: saturne-support@edf.fr
#
#     The Code_Saturne Kernel is free software; you can redistribute it
#     and/or modify it under the terms of the GNU General Public License
#     as published by the Free Software Foundation; either version 2 of
#     the License, or (at your option) any later version.
#
#     The Code_Saturne Kernel is distributed in the hope that it will be
#     useful, but WITHOUT ANY WARRANTY; without even the implied warranty
#     of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with the Code_Saturne Kernel; if not, write to the
#     Free Software Foundation, Inc.,
#     51 Franklin St, Fifth Floor,
#     Boston, MA  02110-1301  USA
#
#============================================================================

import sys
from xml.dom import minidom

#-------------------------------------------------------------------------------
# Utility class
#-------------------------------------------------------------------------------

class XMLError(Exception):
    """Base class for exception handling."""

    def __init__(self, *args):
        self.args = args

    def __str__(self):
        if len(self.args) == 1:
            return str(self.args[0])
        else:
            return str(self.args)

#-------------------------------------------------------------------------------
# Utility functions
#-------------------------------------------------------------------------------

def getChildNode(node, tag, required=False):
    """
    Return a child node matching a tag.
    """
    childNode = None
    for child in node.childNodes:
        if child.nodeType == node.ELEMENT_NODE:
            if child.nodeName == tag:
                if childNode == None:
                    childNode = child
                else:
                    errStr = "Multiple instance of " + tag + "nodes"
                    raise XMLError(errStr)

    if childNode == None and required:
        errStr = tag + " node not found under " + node.tagName
        raise XMLError(errStr)

    return childNode

#-------------------------------------------------------------------------------

def childNodeList(node, tag):
    """
    Return a list of child nodes matching a tag.
    """
    childNodeList = []
    for child in node.childNodes:
        if child.nodeType == node.ELEMENT_NODE:
            if child.nodeName == tag:
                childNodeList.append(child)

    return childNodeList

#-------------------------------------------------------------------------------

def getDataFromNode(node, tag):
    """
    Return data matching a tag.
    """
    data = None
    list = node.getElementsByTagName(tag)

    if (list.length == 1):
        current = list.item(0)
        data = current.firstChild.data

    return data

#-------------------------------------------------------------------------------
# Main class
#-------------------------------------------------------------------------------

class Parser:
    """Extract case information from XML file."""

    #---------------------------------------------------------------------------

    def __init__(self,
                 fileName,
                 root_str = None,
                 version_str = None):

        self.dict = {}
        self.dict['mesh_dir'] = None
        self.dict['meshes'] = None

        self.root = None

        if fileName == None:
            return

        try:
            self.doc = minidom.parse(fileName)
        except Exception:
            raise XMLError('Error parsing XML file: ' + fileName)

        self.root = self.doc.documentElement

        if root_str != None:
            if root_str != self.root.tagName:
                errStr = '%s\n' \
                    +'type: "%s", but "%s" expected.'
                raise XMLError(errStr % (fileName,
                                         self.root.tagName,
                                         root_str))

        if version_str != None:
            version = self.root.getAttribute('version')
            if version_str != version:
                errStr = '%s\n' \
                    +'type: "%s", version: "%s", but version "%s" expected.'
                raise XMLError(errStr % (fileName,
                                         self.root.tagName,
                                         version,
                                         version_str))

        # Get study and case names

        study_name = str(self.root.getAttribute('study'))
        case_name = str(self.root.getAttribute('case'))

        if len(study_name) > 0:
            self.dict['study'] = study_name

        if len(case_name) > 0:
            self.dict['case'] = case_name

    #---------------------------------------------------------------------------

    def _getMeshExtension(self, name):
        """
        Return: Extension of the mesh file if it exists.
        """
        # Define known extensions
        ext = {'case':'ensight',
               'cgns':'cgns',
               'des':'des',
               'med':'med',
               'msh':'gmsh',
               'neu':'gambit',
               'ccm':'ccm',
               'ngeom':'ngeom',
               'unv':'ideas'}

        # first check if the mesh is compressed with gzip
        if name.endswith(".gz"):
            name = name[:-3]

        extension = None
        last_caracters = (name.split('.')[-1:])[0]
        if last_caracters in ext.keys():
            extension = last_caracters
        return extension

    #---------------------------------------------------------------------------

    def _getMeshFormat(self, name):
        """
        Return mesh format.
        """
        format = ""
        extension = self._getMeshExtension(mesh)
        if extension:
            format = self.ext[extension]
        return format

    #---------------------------------------------------------------------------

    def _getMeshParams(self):
        """
        Get mesh parameters
        """

        # Search for appropriate node.

        sol_domain_node = getChildNode(self.root, 'solution_domain')
        if sol_domain_node == None:
            return

        # Get mesh_input if available; in this case, no mesh
        # import will be necessary, so we are done.

        node = getChildNode(sol_domain_node, 'mesh_input')
        if node != None:
            mesh_input = str(node.getAttribute('path'))
            if mesh_input:
                self.dict['mesh_input'] = mesh_input
                return

        # Get meshes.

        meshes = []

        meshes_node = getChildNode(sol_domain_node, 'meshes_list')

        if meshes_node != None:

            # Get meshes search directory.
            node = getChildNode(meshes_node, 'meshdir')
            if node != None:
                meshdir = str(node.getAttribute('name'))
                if len(meshdir) > 0:
                    self.dict['mesh_dir'] = meshdir

            # Get meshes list
            nodeList = childNodeList(meshes_node, 'mesh')

        else:
            nodeList = []

        for node in nodeList:

            name = str(node.getAttribute('name'))
            format = str(node.getAttribute('format'))
            number = str(node.getAttribute('num'))
            reorient = (str(node.getAttribute('reorient')) == 'on')
            grp_cel = str(node.getAttribute('grp_cel'))
            grp_fac = str(node.getAttribute('grp_fac'))

            l_args = []
            extension = self._getMeshExtension(name)
            if extension == None and len(format) > 0:
                l_args.append('--format ' + format)
            if len(number) > 0:
                l_args.append('--num ' + number)
            if reorient:
                l_args.append('--reorient')
            if len(grp_cel) > 0:
                l_args.append('--grp-cel ' + grp_cel)
            if len(grp_fac) > 0:
                l_args.append('--grp-fac ' + grp_fac)

            if len(l_args) >  0:
                l_args.insert(0, name)
                meshes.append(tuple(l_args))
            else:
                meshes.append(name)

        if len(meshes) > 0:
            self.dict['meshes'] = meshes

    #---------------------------------------------------------------------------

    def _getInputFiles(self):
        """
        Get input file parameters
        """

        # Search for meteorological and thermochemistry data

        th_models = getChildNode(self.root, 'thermophysical_models')
        if th_models:

            node = getChildNode(th_models, 'atmospheric_flows')
            if node:
                status_node = getChildNode(node, 'read_meteo_data')
                if status_node:
                    if str(status_node.getAttribute('status')) == 'on':
                        self.dict['meteo_data'] = getDataFromNode(node,
                                                                  'meteo_data')

            node = getChildNode(th_models, 'pulverized_coal')
            if node:
                model = str(node.getAttribute('model'))
                if model != 'off': # 'coal_homo' or 'coal_homo2'
                    self.dict['thermochemistry_data'] = 'dp_FCP'

        # Search for user input files

        user_data = []

        calc_node = getChildNode(self.root, 'calculation_management')
        if calc_node:
            input_node = getChildNode(calc_node, 'user_input_files')
            if input_node != None:
                nodeList = childNodeList(input_node, 'data')
                for node in nodeList:
                    name = str(node.getAttribute('name'))
                    if name:
                        user_data.append(name)

        if len(user_data) > 0:
            self.dict['user_input_files'] = user_data

    #---------------------------------------------------------------------------

    def _getCalcParams(self):
        """
        Get various calculation parameters
        """

        # Search for user calculation parameters

        calc_node = getChildNode(self.root, 'calculation_management')
        if not calc_node:
            return

        node = getChildNode(calc_node, 'start_restart')
        if node != None:
            node = getChildNode(node, 'restart')
        if node != None:
            path = str(node.getAttribute('path'))
            if path:
                self.dict['restart_input'] = path

        val = getDataFromNode(calc_node, 'partition_type')
        if val:
            if val == 'scotch':
                self.dict['partition_args'] = '--scotch'
            elif val == 'metis':
                self.dict['partition_args'] = '--metis'
            elif val.find('sfc') > -1:
                self.dict['exec_partition'] = False

        partition_list = getDataFromNode(calc_node, 'partition_list')
        if partition_list:
           self.dict['partition_list'] = partition_list.split()

        val = getDataFromNode(calc_node, 'run_type')
        if val:
            if val == 'none':
                self.dict['exec_solver'] = False
            elif val == 'mesh preprocess':
                self.dict['solver_args'] = '--preprocess'
            elif val == 'mesh quality':
                self.dict['solver_args'] = '--quality'

        logging_args = ''
        log_node = getChildNode(calc_node, 'logging')
        if log_node != None:
            attr = str(log_node.getAttribute('main'))
            if attr == 'stdout':
                logging_args += '--log 0 '
            attr = str(log_node.getAttribute('parallel'))
            if attr == 'stdout':
                logging_args += '--logp 0'
            elif attr == 'listing':
                logging_args += '--logp 1'
        logging_args.strip()

        if logging_args:
            self.dict['logging_args'] = logging_args

        val = getDataFromNode(calc_node, 'valgrind')
        if val:
            self.dict['valgrind'] = val

        # Additional fields relative to the run environment

        for key in ['scratchdir', 'n_procs']:
            val = getDataFromNode(calc_node, key)
            if val:
                self.dict['case_' + key] = val

    #---------------------------------------------------------------------------

    def getParams(self):
        """
        Get all parameters
        """
        self._getMeshParams()
        self._getInputFiles()
        self._getCalcParams()

        return self.dict

#-------------------------------------------------------------------------------
# End
#-------------------------------------------------------------------------------
